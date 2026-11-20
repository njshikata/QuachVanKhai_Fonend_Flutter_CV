// Đường dẫn: lib/Source/api/JsonIsolate.dart
//
// Giải mã JSON ở Isolate phụ bằng compute() để KHÔNG chặn UI thread (tránh giật khung hình
// khi danh sách dài / response lớn).
//
// Payload nhỏ (< 16KB) giải mã luôn trên main isolate: chi phí tạo isolate (~vài ms + copy dữ liệu)
// còn lớn hơn chính việc decode, nên chuyển sang isolate lúc đó lại làm app CHẬM hơn.
// Trên Flutter Web, compute() chạy cùng luồng (web không có isolate) nhưng API giữ nguyên.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:qlpt_frontend/Source/perf/PerfFlags.dart';

class JsonIsolate {
  static const int isolateThresholdBytes = 16 * 1024;

  /// Dùng thay cho `jsonDecode(utf8.decode(response.bodyBytes))`.
  static Future<dynamic> decode(Uint8List bytes) async {
    if (bytes.isEmpty) return null;
    // Tắt tối ưu (PerfFlags) -> parse thẳng trên UI thread để so sánh
    if (!PerfFlags.isolateJson.value || bytes.length < isolateThresholdBytes) return _decode(bytes);
    return compute(_decode, bytes, debugLabel: 'jsonDecode ${bytes.length}B');
  }

  /// Giải mã chuỗi JSON đọc từ database cục bộ.
  static Future<dynamic> decodeString(String s) async {
    if (s.isEmpty) return null;
    if (!PerfFlags.isolateJson.value || s.length < isolateThresholdBytes) return jsonDecode(s);
    return compute(_decodeString, s, debugLabel: 'jsonDecode local ${s.length}');
  }

  // Hàm top-level/static để truyền được sang isolate khác
  static dynamic _decode(Uint8List bytes) => jsonDecode(utf8.decode(bytes));
  static dynamic _decodeString(String s) => jsonDecode(s);
}
