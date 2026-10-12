import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class ApiTotal {
  // ⚠️ QUAN TRỌNG DÀNH CHO ĐIỆN THOẠI THẬT:
  // Nếu bạn cắm cáp test trên ĐIỆN THOẠI THẬT (Android/iOS), hãy điền IP LAN của máy tính vào đây.
  // Ví dụ: static const String physicalDeviceIP = "192.168.1.15";
  // Nếu chỉ chạy trên Máy ảo, Web hoặc Windows, HÃY ĐỂ TRỐNG ("").
  static const String physicalDeviceIP = "";

  // Thay vì dùng hằng số (const), ta dùng getter (get) để tính toán dựa trên môi trường
  static String get baseUrl {

    // 1. Ưu tiên số 1: Dùng IP vật lý nếu bạn có cấu hình (Test trên thiết bị thật)
    if (physicalDeviceIP.isNotEmpty) {
      return "http://$physicalDeviceIP:8080";
    }

    // 2. Nếu chạy trên Trình duyệt Web (Chrome, Edge, Safari...)
    if (kIsWeb) {
      return "http://localhost:8080";
    }

    // 3. Nếu chạy trên App Native (Bắt buộc check kIsWeb trước để Web không bị lỗi dart:io)
    if (Platform.isAndroid) {
      return "http://10.0.2.2:8080";    // Máy ảo Android Emulator
    } else if (Platform.isIOS) {
      return "http://127.0.0.1:8080";   // Máy ảo iOS Simulator
    } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return "http://localhost:8080";   // Ứng dụng Desktop (Windows/Mac)
    }

    // Mặc định an toàn
    return "http://localhost:8080";
  }
}