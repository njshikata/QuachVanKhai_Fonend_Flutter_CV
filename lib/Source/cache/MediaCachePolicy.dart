// Đường dẫn: lib/Source/cache/MediaCachePolicy.dart
//
// CHÍNH SÁCH LƯU ẢNH TRÊN MÁY
//  1. Ảnh chỉ được giữ tối đa 90 ngày KỂ TỪ LÚC TẢI VỀ -> quá hạn xóa, lần xem sau tự tải lại từ server.
//     (Server giữ ảnh 1-2 năm; quá hạn server trả 204 rỗng -> widget hiện ảnh mặc định.)
//  2. Versioning: cache key có version (vd "card-photo:12:v3"). Khi ảnh/version mới được tải,
//     các version cũ cùng nhóm bị xóa ngay -> không bao giờ hiện ảnh cũ sau khi đổi thông tin.
//  3. Đổi chủ phòng: dữ liệu ảnh của CHỦ CŨ trong phòng đó bị xóa khỏi máy sau 30 ngày kể từ lúc đổi.
//
// Chỉ lưu 1 chỉ mục nhỏ (JSON) trong SharedPreferences; file ảnh do AppCacheManager quản lý.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'AppCacheManager.dart';

class MediaCacheTag {
  final String? group;   // VD "card-photo:12" (cùng 1 thẻ, khác version)
  final int? ownerId;    // Người sở hữu dữ liệu (tenantId)
  final int? roomId;

  const MediaCacheTag({this.group, this.ownerId, this.roomId});
}

class MediaCachePolicy {
  static const Duration maxAge = AppCacheManager.maxAge;          // 3 tháng
  static const Duration ownerChangeGrace = Duration(days: 30);    // 1 tháng sau đổi chủ

  static const String _indexKey = 'media_cache_index_v1';
  static const String _ownersKey = 'media_room_owner_v1';

  static Map<String, dynamic>? _index;   // key -> {t: storedAt, g, o, r}
  static Map<String, dynamic>? _owners;  // roomId -> {cur, old, at}
  static Future<void>? _cleanup;
  static final Set<String> _trackedThisSession = {};

  /// Đồng hồ của chính sách. Bộ test tối ưu (TestSuiteScreen) tạm "tua nhanh" đồng hồ này để kiểm tra
  /// luật 90 ngày / 30 ngày đổi chủ mà không phải chờ thật. Ứng dụng thật luôn dùng DateTime.now.
  static DateTime Function() clock = DateTime.now;

  /// Chạy dọn dẹp ngay (bỏ qua giới hạn 1 lần/phiên) – chỉ dùng cho bộ test.
  static Future<void> runCleanupNow() => _runCleanup();

  /// Ảnh [key] còn được ghi nhận trong chỉ mục cache của máy không – chỉ dùng cho bộ test.
  static Future<bool> isTracked(String key) async {
    await _load();
    return _index!.containsKey(key);
  }

  /// Chạy dọn dẹp 1 lần mỗi phiên (gọi tự động từ AppNetworkImage).
  static Future<void> ensureCleaned() => _cleanup ??= _runCleanup();

  /// Ghi nhận ảnh vừa hiển thị thành công.
  static Future<void> track(String key, MediaCacheTag? tag) async {
    if (!_trackedThisSession.add(key)) return;
    await _load();
    final index = _index!;
    if (!index.containsKey(key)) {
      index[key] = {
        't': clock().millisecondsSinceEpoch,
        if (tag?.group != null) 'g': tag!.group,
        if (tag?.ownerId != null) 'o': tag!.ownerId,
        if (tag?.roomId != null) 'r': tag!.roomId,
      };
    }
    // Versioning: xóa các version cũ cùng nhóm
    if (tag?.group != null) {
      final stale = index.entries
          .where((e) => e.key != key && (e.value as Map)['g'] == tag!.group)
          .map((e) => e.key)
          .toList();
      for (final k in stale) {
        await _remove(k);
      }
    }
    await _save();
  }

  /// Gọi mỗi khi nhận thông tin phòng/thẻ từ server để phát hiện đổi chủ phòng.
  static Future<void> onRoomOwner({
    required int roomId,
    required int currentOwnerId,
    int? previousOwnerId,
    DateTime? ownerChangedAt,
  }) async {
    await _load();
    final owners = _owners!;
    final rk = roomId.toString();
    final saved = owners[rk] as Map<String, dynamic>?;

    if (previousOwnerId != null && ownerChangedAt != null) {
      owners[rk] = {'cur': currentOwnerId, 'old': previousOwnerId, 'at': ownerChangedAt.millisecondsSinceEpoch};
    } else if (saved != null && saved['cur'] != currentOwnerId) {
      // Server không báo nhưng máy phát hiện chủ phòng khác lần trước
      owners[rk] = {'cur': currentOwnerId, 'old': saved['cur'], 'at': clock().millisecondsSinceEpoch};
    } else if (saved == null) {
      owners[rk] = {'cur': currentOwnerId};
    }
    await _purgeOldOwner(rk);
    await _save();
  }

  /// Xóa toàn bộ (VD khi đăng xuất trên máy dùng chung).
  static Future<void> clearAll() async {
    await AppCacheManager.instance.emptyCache();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_indexKey);
    await prefs.remove(_ownersKey);
    _index = {};
    _owners = {};
    _trackedThisSession.clear();
  }

  // ============================ nội bộ ============================
  static Future<void> _runCleanup() async {
    try {
      await _load();
      final now = clock().millisecondsSinceEpoch;
      final expired = _index!.entries
          .where((e) => now - ((e.value as Map)['t'] as int) > maxAge.inMilliseconds)
          .map((e) => e.key)
          .toList();
      for (final k in expired) {
        await _remove(k);
      }
      for (final rk in _owners!.keys.toList()) {
        await _purgeOldOwner(rk);
      }
      await _save();
      if (expired.isNotEmpty) debugPrint('[MediaCache] Đã xóa ${expired.length} ảnh quá 90 ngày');
    } catch (e) {
      debugPrint('[MediaCache] Lỗi dọn cache: $e');
    }
  }

  static Future<void> _purgeOldOwner(String rk) async {
    final info = _owners![rk] as Map<String, dynamic>?;
    if (info == null || info['old'] == null || info['at'] == null) return;
    final changedAt = DateTime.fromMillisecondsSinceEpoch(info['at'] as int);
    if (clock().difference(changedAt) < ownerChangeGrace) return;

    final roomId = int.parse(rk);
    final oldOwner = info['old'];
    final keys = _index!.entries
        .where((e) => (e.value as Map)['r'] == roomId && (e.value as Map)['o'] == oldOwner)
        .map((e) => e.key)
        .toList();
    for (final k in keys) {
      await _remove(k);
    }
    _owners![rk] = {'cur': info['cur']}; // Đã dọn xong
    if (keys.isNotEmpty) debugPrint('[MediaCache] Đổi chủ phòng $roomId: đã xóa ${keys.length} ảnh của chủ cũ');
  }

  static Future<void> _remove(String key) async {
    _index!.remove(key);
    _trackedThisSession.remove(key);
    try {
      await AppCacheManager.instance.removeFile(key);
    } catch (_) {}
  }

  static Future<void> _load() async {
    if (_index != null && _owners != null) return;
    final prefs = await SharedPreferences.getInstance();
    _index = _decode(prefs.getString(_indexKey));
    _owners = _decode(prefs.getString(_ownersKey));
  }

  static Map<String, dynamic> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  static Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_indexKey, jsonEncode(_index));
    await prefs.setString(_ownersKey, jsonEncode(_owners));
  }
}
