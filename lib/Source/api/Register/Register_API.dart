// Đường dẫn: lib/Source/api/Login/Register_API.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../API_total.dart'; // Chỉnh lại đường dẫn này nếu thư mục của bạn khác
import 'Register_DTO.dart';

class RegisterAPI {
  // Hàm gọi API Đăng ký tài khoản
  static Future<String> registerUser(RegisterRequest request) async {
    final url = Uri.parse('${ApiTotal.baseUrl}/api/auth/register');

    try {
      final response = await http.post(
        url,
        // DÙNG publicHeaders ĐỂ ĐÍNH KÈM CHỮ KÝ RSA CHỐNG SPAM (API công khai không cần Token)
        headers: ApiTotal.publicHeaders,
        body: jsonEncode(request.toJson()),
      );

      // Giải mã UTF-8 để giữ chuẩn Tiếng Việt từ Spring Boot
      String responseBody = utf8.decode(response.bodyBytes);

      // Nếu HTTP 200 OK -> Trả về câu thông báo thành công
      if (response.statusCode == 200) {
        return responseBody;
      }
      // Nếu HTTP 400 (Lỗi validate, trùng email...) -> Ném lỗi ra màn hình
      else {
        throw Exception(responseBody);
      }
    } catch (e) {
      throw Exception(e.toString().replaceAll("Exception: ", ""));
    }
  }
}