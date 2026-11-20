// Đường dẫn: lib/Source/security/Security.dart

import 'package:flutter/foundation.dart';
import 'package:qlpt_frontend/Source/api/SyncedApi.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Security {
  static const String _tokenKey = "JWT_TOKEN";
  static const String _roleKey = "USER_ROLE";

  // Giữ token trong RAM: khỏi đọc SharedPreferences cho mỗi request
  static String? _token;
  static bool _loaded = false;

  // Lưu Token và Quyền vào máy
  static Future<void> saveAuthData(String token, String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_roleKey, role);
    _token = token;
    _loaded = true;
    // KHÔNG in token ra log (log có thể bị đọc qua adb logcat)
    debugPrint("[Security] Đăng nhập thành công, role: $role");
  }

  // Lấy Token ra để gắn vào các API khác (VD: Thêm phòng trọ)
  static Future<String?> getToken() async {
    if (_loaded) return _token;
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    _loaded = true;
    return _token;
  }

  // Lấy Quyền để quyết định xem chuyển hướng sang Màn hình Chủ trọ hay Người thuê
  static Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_roleKey);
  }

  // Xóa dữ liệu khi Đăng xuất (kèm database phụ của tài khoản này)
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_roleKey);
    _token = null;
    _loaded = true;
    await SyncedApi.clear();
    debugPrint("[Security] Đã đăng xuất và xóa dữ liệu cục bộ");
  }
}
