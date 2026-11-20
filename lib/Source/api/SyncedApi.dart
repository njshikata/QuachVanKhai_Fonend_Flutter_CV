// Đường dẫn: lib/Source/api/SyncedApi.dart
//
// GỌI API GET CÓ CƠ CHẾ "UPDATE" (ETag / 304) + DATABASE PHỤ (LocalDb)
//
//  1. Gửi GET kèm "If-None-Match: <etag lần trước>".
//  2. Server trả 304 (dữ liệu không đổi) -> dùng bản đã có trong RAM/SQLite: không tải body, không parse JSON.
//     Server trả 200 (có thay đổi)       -> parse ở isolate (JsonIsolate), lưu bản mới + ETag mới.
//  3. Mất mạng -> trả bản trong máy (nếu có) để app vẫn hiển thị được.
//  4. Các lời gọi trùng nhau cùng lúc (vd 4 màn hình cùng gọi dashboard) được gộp thành 1 request.
//
// DỮ LIỆU NHẠY CẢM: trước khi ghi xuống SQLite, các trường trong [sensitiveKeys] bị xóa khỏi JSON.
//  - Bản đầy đủ chỉ nằm trong RAM của phiên hiện tại.
//  - Nếu có trường bị xóa thì KHÔNG lưu ETag xuống đĩa (bản trên đĩa đã khác server), nên lần mở app sau
//    vẫn tải bản đầy đủ từ server; bản trên đĩa chỉ dùng để vẽ màn hình ngay lập tức / khi offline.
//  - API thẻ, OTP, thanh toán, ảnh CCCD... KHÔNG đi qua lớp này (luôn lấy mới từ server).

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../local/LocalDb.dart';
import '../perf/PerfFlags.dart';
import 'API_total.dart';
import 'JsonIsolate.dart';

class ApiStatusException implements Exception {
  final int statusCode;
  final String body;

  const ApiStatusException(this.statusCode, this.body);

  @override
  String toString() => body;
}

class _MemEntry {
  final String? etag;
  final dynamic data;

  const _MemEntry(this.etag, this.data);
}

/// Bộ đếm để báo cáo: bao nhiêu request, bao nhiêu lần server trả 304, tổng byte đã tải.
class SyncStats {
  int requests = 0;
  int notModified = 0;
  int fullResponses = 0;
  int offlineHits = 0;
  int bytesDownloaded = 0;

  void reset() => requests = notModified = fullResponses = offlineHits = bytesDownloaded = 0;

  @override
  String toString() =>
      'Request: $requests | 304: $notModified | 200: $fullResponses | Offline: $offlineHits | Tải: ${(bytesDownloaded / 1024).toStringAsFixed(1)} KB';
}

class SyncedApi {
  static final SyncStats stats = SyncStats();

  /// Tên trường KHÔNG được ghi xuống máy (so khớp không phân biệt hoa thường).
  static const Set<String> sensitiveKeys = {
    'phonenumber', 'phone', 'email',
    'identitynumber', 'identitycard', 'cccd', 'citizenid', 'dateofbirth',
    'password', 'token', 'fcmtoken', 'pin', 'otp',
    'balance', 'accountnumber', 'bankaccount', 'carduid',
  };

  static const Duration _timeout = Duration(seconds: 15);

  static final Map<String, _MemEntry> _mem = {};
  static final Map<String, Future<dynamic>> _inflight = {};
  static String? _ownerToken;
  static String _owner = 'anonymous';

  /// GET [path] (vd "/api/tenant/my-room") với ETag + cache. Trả JSON đã decode.
  static Future<dynamic> getJson(String path) async {
    final headers = Map<String, String>.from(await ApiTotal.getAuthHeaders() as Map);
    final owner = _ownerOf(headers['Authorization']);
    final memKey = '$owner|$path';
    if (!PerfFlags.etagLocalDb.value) return _plainGet(path, headers); // Chế độ "không tối ưu"
    return _inflight[memKey] ??= _fetch(path, owner, memKey, headers).whenComplete(() => _inflight.remove(memKey));
  }

  /// Dữ liệu đang có trong máy (RAM hoặc SQLite), KHÔNG gọi mạng -> vẽ màn hình ngay khi mở.
  /// Có thể thiếu các trường nhạy cảm. null = chưa có.
  static Future<dynamic> peek(String path) async {
    if (!PerfFlags.etagLocalDb.value) return null;
    final headers = Map<String, String>.from(await ApiTotal.getAuthHeaders() as Map);
    final owner = _ownerOf(headers['Authorization']);
    final mem = _mem['$owner|$path'];
    if (mem != null) return mem.data;
    final row = await LocalDb.get(path, owner);
    return row == null ? null : JsonIsolate.decodeString(row.body);
  }

  /// Xóa toàn bộ dữ liệu cục bộ (đăng xuất).
  static Future<void> clear() async {
    _mem.clear();
    _inflight.clear();
    _ownerToken = null;
    _owner = 'anonymous';
    await LocalDb.clear();
  }

  // ============================ nội bộ ============================

  /// GET thường: không ETag, không database phụ, không gộp request.
  static Future<dynamic> _plainGet(String path, Map<String, String> headers) async {
    stats.requests++;
    final res = await http.get(Uri.parse('${ApiTotal.baseUrl}$path'), headers: headers).timeout(_timeout);
    stats.bytesDownloaded += res.bodyBytes.length;
    if (res.statusCode != 200) throw ApiStatusException(res.statusCode, utf8.decode(res.bodyBytes));
    stats.fullResponses++;
    return JsonIsolate.decode(res.bodyBytes);
  }

  static Future<dynamic> _fetch(String path, String owner, String memKey, Map<String, String> headers) async {
    final mem = _mem[memKey];
    LocalRow? disk;
    var etag = mem?.etag;
    if (mem == null) {
      disk = await LocalDb.get(path, owner);
      etag = disk?.etag;
    }
    final reqHeaders = {...headers}..remove('Content-Type');
    if (etag != null) reqHeaders['If-None-Match'] = etag;

    final http.Response res;
    stats.requests++;
    try {
      res = await http.get(Uri.parse('${ApiTotal.baseUrl}$path'), headers: reqHeaders).timeout(_timeout);
    } catch (e) {
      // Offline / server không phản hồi -> dùng bản trong máy nếu có
      if (mem != null) return mem.data;
      disk ??= await LocalDb.get(path, owner);
      if (disk != null) {
        stats.offlineHits++;
        debugPrint('[SyncedApi] Offline, dùng dữ liệu lưu lúc ${disk.savedAt}: $path');
        return JsonIsolate.decodeString(disk.body);
      }
      rethrow;
    }

    stats.bytesDownloaded += res.bodyBytes.length;
    if (res.statusCode == 304) stats.notModified++;
    if (res.statusCode == 200) stats.fullResponses++;
    if (res.statusCode == 304) {
      if (mem != null) return mem.data;
      if (disk != null) {
        final data = await JsonIsolate.decodeString(disk.body);
        _mem[memKey] = _MemEntry(etag, data);
        unawaited(LocalDb.touch(path, owner));
        return data;
      }
    }

    if (res.statusCode == 200) {
      final data = await JsonIsolate.decode(res.bodyBytes);
      final newEtag = res.headers['etag'];
      _mem[memKey] = _MemEntry(newEtag, data);
      unawaited(_persist(path, owner, newEtag, data, res.bodyBytes.length));
      return data;
    }

    if (res.statusCode == 304) {
      // Có ETag nhưng mất bản dữ liệu (hiếm) -> tải lại đầy đủ
      _mem.remove(memKey);
      final retry = {...reqHeaders}..remove('If-None-Match');
      final full = await http.get(Uri.parse('${ApiTotal.baseUrl}$path'), headers: retry).timeout(_timeout);
      if (full.statusCode == 200) {
        final data = await JsonIsolate.decode(full.bodyBytes);
        _mem[memKey] = _MemEntry(full.headers['etag'], data);
        unawaited(_persist(path, owner, full.headers['etag'], data, full.bodyBytes.length));
        return data;
      }
      throw ApiStatusException(full.statusCode, utf8.decode(full.bodyBytes));
    }

    throw ApiStatusException(res.statusCode, utf8.decode(res.bodyBytes));
  }

  static Future<void> _persist(String path, String owner, String? etag, dynamic data, int size) async {
    if (!LocalDb.supported) return;
    try {
      final result = size < JsonIsolate.isolateThresholdBytes
          ? _sanitizeAndEncode(data)
          : await compute(_sanitizeAndEncode, data, debugLabel: 'sanitize $path');
      final stripped = result['stripped'] as bool;
      await LocalDb.put(path, owner, etag: stripped ? null : etag, body: result['body'] as String);
    } catch (e) {
      debugPrint('[SyncedApi] Không lưu được cache $path: $e');
    }
  }

  /// Chủ sở hữu dữ liệu = SHA-256 của "sub" trong JWT (không lưu email/username dạng rõ).
  static String _ownerOf(String? authorization) {
    if (authorization == null || !authorization.startsWith('Bearer ')) return 'anonymous';
    final token = authorization.substring(7);
    if (token == _ownerToken) return _owner;
    var subject = token;
    try {
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))));
      subject = (payload['sub'] ?? payload['userId'] ?? token).toString();
    } catch (_) {}
    _ownerToken = token;
    _owner = sha256.convert(utf8.encode(subject)).toString().substring(0, 32);
    return _owner;
  }
}

// Top-level để chạy được trong compute()
Map<String, Object> _sanitizeAndEncode(dynamic data) {
  var stripped = false;
  dynamic walk(dynamic v) {
    if (v is Map) {
      final out = <String, dynamic>{};
      v.forEach((k, val) {
        if (SyncedApi.sensitiveKeys.contains(k.toString().toLowerCase())) {
          stripped = true;
        } else {
          out[k.toString()] = walk(val);
        }
      });
      return out;
    }
    if (v is List) return v.map(walk).toList();
    return v;
  }

  final body = jsonEncode(walk(data));
  return {'body': body, 'stripped': stripped};
}
