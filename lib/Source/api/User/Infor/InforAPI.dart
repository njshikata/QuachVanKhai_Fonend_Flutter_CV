// Đường dẫn: lib/Source/api/User/Total/InforAPI.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:qlpt_frontend/Source/api/API_total.dart';
import 'package:qlpt_frontend/Source/security/Security.dart';
import 'InforDTO.dart';

class InforAPI {
  // Thay url này theo đúng cấu trúc của bạn
  static String get baseUrl => '${ApiTotal.baseUrl}/api/profile';

  static Future<Map<String, String>> _getHeaders() async {
    String? token = await Security.getToken();
    if (token == null || token.isEmpty) {
      throw Exception("Vui lòng đăng nhập lại!");
    }
    return {
      "Content-Type": "application/json",
      "Accept": "application/json",
      "Authorization": "Bearer $token",
    };
  }

  // API lấy thông tin Profile đang đăng nhập
  static Future<UserProfileResponse> getMyProfile() async {
    final url = Uri.parse('$baseUrl/me');
    try {
      final response = await http.get(url, headers: await _getHeaders());
      if (response.statusCode == 200) {
        return UserProfileResponse.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      throw Exception(e.toString().replaceAll("Exception: ", ""));
    }
  }
}