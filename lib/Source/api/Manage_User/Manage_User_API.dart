// Đường dẫn: lib/Source/api/Manage_User/Manage_User_API.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:qlpt_frontend/Source/api/API_total.dart';
import 'package:qlpt_frontend/Source/security/Security.dart';
import 'Manage_User_DTO.dart';

class ManageUserAPI {
  static String get baseUrl => '${ApiTotal.baseUrl}/api/landlady/users';

  static Future<Map<String, String>> _getHeaders() async {
    String? token = await Security.getToken();
    if (token != null && token.isNotEmpty) {
      return {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      };
    } else {
      return {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
    }
  }

  static Future<List<ManageUserDTO>> getAllUsers() async {
    final headers = await _getHeaders();
    final response = await http.get(Uri.parse(baseUrl), headers: headers);

    if (response.statusCode == 200) {
      List<dynamic> jsonList = jsonDecode(utf8.decode(response.bodyBytes));
      return jsonList.map((json) => ManageUserDTO.fromJson(json)).toList();
    } else {
      throw Exception(utf8.decode(response.bodyBytes));
    }
  }

  static Future<ManageUserDTO> getUserById(int id) async {
    final headers = await _getHeaders();
    final response = await http.get(Uri.parse('$baseUrl/$id'), headers: headers);

    if (response.statusCode == 200) {
      return ManageUserDTO.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
    } else {
      throw Exception(utf8.decode(response.bodyBytes));
    }
  }

  static Future<ManageUserDTO> createUser(ManageUserDTO userDTO) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse(baseUrl),
      headers: headers,
      body: jsonEncode(userDTO.toJson()),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      return ManageUserDTO.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
    } else {
      throw Exception(utf8.decode(response.bodyBytes));
    }
  }

  static Future<ManageUserDTO> updateUser(int id, ManageUserDTO userDTO) async {
    final headers = await _getHeaders();
    final response = await http.put(
      Uri.parse('$baseUrl/$id'),
      headers: headers,
      body: jsonEncode(userDTO.toJson()),
    );

    if (response.statusCode == 200) {
      return ManageUserDTO.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
    } else {
      throw Exception(utf8.decode(response.bodyBytes));
    }
  }

  // === MỚI: THAY THẾ HÀM XÓA BẰNG HÀM LẤY LỊCH SỬ ===
  static Future<List<TenantHistory>> getUserHistory(int id) async {
    final headers = await _getHeaders();
    final response = await http.get(Uri.parse('$baseUrl/$id/history'), headers: headers);

    if (response.statusCode == 200) {
      List<dynamic> jsonList = jsonDecode(utf8.decode(response.bodyBytes));
      return jsonList.map((json) => TenantHistory.fromJson(json)).toList();
    } else {
      throw Exception(utf8.decode(response.bodyBytes));
    }
  }
}