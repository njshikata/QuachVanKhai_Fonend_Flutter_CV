import 'dart:convert';
import 'package:http/http.dart' as http;
import '../API_total.dart';
import 'LoginDTO.dart';
import '../../security/Security.dart';

class LoginAPI {
  // Hàm đăng nhập trả về thông báo (Thành công hoặc Lỗi)
  static Future<String> login(String email, String password) async {
    final url = Uri.parse('${ApiTotal.baseUrl}/api/auth/login');
    final requestBody = LoginRequest(email: email, password: password);

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(requestBody.toJson()),
      );

      if (response.statusCode == 200) {
        // HTTP 200 OK: Spring Boot cho phép đăng nhập
        // Giải mã JSON (Dùng utf8.decode để không bị lỗi font tiếng Việt)
        final Map<String, dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        LoginResponse loginResponse = LoginResponse.fromJson(data);

        // Lưu Token và Role vào Két sắt (Security)
        await Security.saveAuthData(loginResponse.token, loginResponse.role);

        return "SUCCESS"; // Đăng nhập thành công
      } else {
        // HTTP 400: Sai email/mật khẩu -> Trả về đúng câu lỗi của Spring Boot
        return utf8.decode(response.bodyBytes);
      }
    } catch (e) {
      // Bắt lỗi không bật Server hoặc mất mạng
      return "Không thể kết nối đến máy chủ. Vui lòng kiểm tra lại mạng!";
    }
  }
}