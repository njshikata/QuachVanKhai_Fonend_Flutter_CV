// Đường dẫn: lib/Source/security/Security.dart

import 'package:shared_preferences/shared_preferences.dart';

class Security {
  static const String _tokenKey = "JWT_TOKEN";
  static const String _roleKey = "USER_ROLE";

  // Lưu Token và Quyền vào máy
  static Future<void> saveAuthData(String token, String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_roleKey, role);

    // SOUT (PRINT) TOKEN KHI LƯU: Để kiểm tra lúc đăng nhập thành công
    print("========== THÔNG TIN ĐĂNG NHẬP ==========");
    print("Role đã lưu: $role");
    print("Token đã lưu: $token");
    print("=========================================");
  }

  // Lấy Token ra để gắn vào các API khác (VD: Thêm phòng trọ)
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString(_tokenKey);

    // SOUT (PRINT) TOKEN KHI LẤY RA: Để kiểm tra khi gọi các API cần xác thực
    print("--- [Security] Get Token: $token ---");
    return token;
  }

  // Lấy Quyền để quyết định xem chuyển hướng sang Màn hình Chủ trọ hay Người thuê
  static Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    String? role = prefs.getString(_roleKey);
    return role;
  }

  // Xóa dữ liệu khi Đăng xuất
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_roleKey);

    // In ra thông báo khi đăng xuất
    print("========== ĐÃ XÓA TOKEN VÀ ĐĂNG XUẤT ==========");
  }
}