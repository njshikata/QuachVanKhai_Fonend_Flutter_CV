// Đường dẫn: lib/Source/api/Manage_User/Manage_User_API.dart

import 'package:qlpt_frontend/Source/api/JsonIsolate.dart';
import 'package:qlpt_frontend/Source/api/SyncedApi.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:qlpt_frontend/Source/api/API_total.dart';
import 'Manage_User_DTO.dart';

class ManageUserAPI {
  static String get baseUrl => '${ApiTotal.baseUrl}/api/landlady/users';

  // SỬ DỤNG HÀM TỔNG TỪ ApiTotal ĐỂ TỰ ĐỘNG CÓ RSA HANDSHAKE VÀ TOKEN
  static Future _getHeaders() async {
    return await ApiTotal.getAuthHeaders();
  }

  // GET dùng ETag + database phụ (SĐT/email/CCCD không ghi xuống máy)
  static Future<List<ManageUserDTO>> getAllUsers() async {
    final List<dynamic> jsonList = await SyncedApi.getJson('/api/landlady/users');
    return jsonList.map((json) => ManageUserDTO.fromJson(json)).toList();
  }

  static Future<ManageUserDTO> getUserById(int id) async {
    return ManageUserDTO.fromJson(await SyncedApi.getJson('/api/landlady/users/$id'));
  }

  static Future<ManageUserDTO> createUser(ManageUserDTO userDTO) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse(baseUrl),
      headers: headers,
      body: jsonEncode(userDTO.toJson()),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      return ManageUserDTO.fromJson(await JsonIsolate.decode(response.bodyBytes));
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
      return ManageUserDTO.fromJson(await JsonIsolate.decode(response.bodyBytes));
    } else {
      throw Exception(utf8.decode(response.bodyBytes));
    }
  }

  // === LẤY LỊCH SỬ NGƯỜI DÙNG ===
  static Future<List<TenantHistory>> getUserHistory(int id) async {
    final List<dynamic> jsonList = await SyncedApi.getJson('/api/landlady/users/$id/history');
    return jsonList.map((json) => TenantHistory.fromJson(json)).toList();
  }
}
