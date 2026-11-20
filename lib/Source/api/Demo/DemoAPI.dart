// Đường dẫn: lib/Source/api/Demo/DemoAPI.dart
//
// API dữ liệu demo / test hiệu năng (/api/landlord/demo) – chỉ tài khoản CHỦ TRỌ.

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:qlpt_frontend/Source/api/API_total.dart';
import 'package:qlpt_frontend/Source/api/SmartCard/SmartCardDTO.dart' show PageResult;
import 'package:qlpt_frontend/Source/api/SyncedApi.dart';

class DemoScale {
  final String label;
  final int properties;
  final int roomsPerProperty;
  final int months;
  final int logsPerCard;

  const DemoScale(this.label, this.properties, this.roomsPerProperty, this.months, this.logsPerCard);

  int get rooms => properties * roomsPerProperty;

  static const small = DemoScale('Nhỏ', 5, 20, 6, 20);
  static const medium = DemoScale('Vừa', 20, 50, 12, 60);
  static const large = DemoScale('Lớn', 50, 80, 24, 150);
  static const values = [small, medium, large];
}

class DemoItem {
  final int id;
  final String title;
  final String room;
  final int amount;
  final String status;
  final int area;
  final String createdAt;
  final String imageUrl;
  final List<String> tags;
  final String description;
  final bool starred; // Trạng thái cục bộ để test "đổi 1 item"

  const DemoItem({
    required this.id,
    required this.title,
    required this.room,
    required this.amount,
    required this.status,
    required this.area,
    required this.createdAt,
    required this.imageUrl,
    required this.tags,
    required this.description,
    this.starred = false,
  });

  factory DemoItem.fromJson(Map<String, dynamic> j) => DemoItem(
        id: (j['id'] as num?)?.toInt() ?? 0,
        title: j['title']?.toString() ?? '',
        room: j['room']?.toString() ?? '',
        amount: (j['amount'] as num?)?.toInt() ?? 0,
        status: j['status']?.toString() ?? '',
        area: (j['area'] as num?)?.toInt() ?? 0,
        createdAt: j['createdAt']?.toString() ?? '',
        imageUrl: j['imageUrl']?.toString() ?? '',
        tags: ((j['tags'] as List?) ?? const []).map((e) => e.toString()).toList(),
        description: j['description']?.toString() ?? '',
      );

  DemoItem toggleStar() => DemoItem(
        id: id, title: title, room: room, amount: amount, status: status, area: area, createdAt: createdAt,
        imageUrl: imageUrl, tags: tags, description: description, starred: !starred,
      );
}

class DemoAPI {
  static const String _base = '/api/landlord/demo';

  static String feedPath({required int page, required int size, required int total}) =>
      '$_base/feed?page=$page&size=$size&total=$total';

  static Future<dynamic> _send(String method, String path, {Duration timeout = const Duration(seconds: 30)}) async {
    final headers = Map<String, String>.from(await ApiTotal.getAuthHeaders() as Map);
    final uri = Uri.parse('${ApiTotal.baseUrl}$path');
    final res = await (method == 'POST'
            ? http.post(uri, headers: headers)
            : method == 'DELETE'
                ? http.delete(uri, headers: headers)
                : http.get(uri, headers: headers))
        .timeout(timeout);
    final body = utf8.decode(res.bodyBytes);
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw Exception('Cần đăng nhập tài khoản CHỦ TRỌ để dùng dữ liệu demo');
    }
    if (res.statusCode != 200) throw Exception('Lỗi ${res.statusCode}: $body');
    return jsonDecode(body);
  }

  /// Sinh dữ liệu: có thể mất 10–60 giây với quy mô lớn.
  static Future<Map<String, dynamic>> seed(DemoScale s) async => Map<String, dynamic>.from(await _send(
        'POST',
        '$_base/seed?properties=${s.properties}&roomsPerProperty=${s.roomsPerProperty}'
            '&months=${s.months}&logsPerCard=${s.logsPerCard}',
        timeout: const Duration(minutes: 5),
      ));

  static Future<Map<String, dynamic>> wipe() async =>
      Map<String, dynamic>.from(await _send('DELETE', '$_base/seed', timeout: const Duration(minutes: 2)));

  static Future<Map<String, dynamic>> stats() async => Map<String, dynamic>.from(await _send('GET', '$_base/stats'));

  /// 1 trang feed (qua SyncedApi -> có ETag/DB phụ khi bật). size <= 0 => toàn bộ.
  static Future<PageResult<DemoItem>> feed(int page, int size, int total) async {
    final data = await SyncedApi.getJson(feedPath(page: page, size: size, total: total));
    return PageResult.fromJson(Map<String, dynamic>.from(data as Map), DemoItem.fromJson);
  }

  /// Tải thô (không parse) để đo riêng thời gian parse JSON.
  static Future<Uint8List> rawFeed(int total) async {
    final headers = Map<String, String>.from(await ApiTotal.getAuthHeaders() as Map);
    final res = await http
        .get(Uri.parse('${ApiTotal.baseUrl}${feedPath(page: 0, size: 0, total: total)}'), headers: headers)
        .timeout(const Duration(minutes: 1));
    if (res.statusCode != 200) throw Exception('Lỗi ${res.statusCode}');
    return res.bodyBytes;
  }
}
