// Đường dẫn: lib/Source/api/User/UserAPI.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:qlpt_frontend/Source/api/API_total.dart';
import 'package:qlpt_frontend/Source/security/Security.dart';
import 'UserDTO.dart';

class UserAPI {
  static String get baseUrl => '${ApiTotal.baseUrl}/api/tenant';

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

  // 1. API lấy thông tin phòng đang thuê
  static Future<MyRoomResponse> getMyRoomInfo() async {
    final url = Uri.parse('$baseUrl/my-room');
    try {
      final response = await http.get(url, headers: await _getHeaders());
      if (response.statusCode == 200) {
        return MyRoomResponse.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      throw Exception(e.toString().replaceAll("Exception: ", ""));
    }
  }

  // 2. API lấy danh sách hóa đơn (lịch sử và tháng hiện tại)
  static Future<List<MyInvoiceResponse>> getMyInvoices() async {
    final url = Uri.parse('$baseUrl/my-invoices');
    try {
      final response = await http.get(url, headers: await _getHeaders());
      if (response.statusCode == 200) {
        List<dynamic> jsonList = jsonDecode(utf8.decode(response.bodyBytes));
        return jsonList.map((json) => MyInvoiceResponse.fromJson(json)).toList();
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      throw Exception(e.toString().replaceAll("Exception: ", ""));
    }
  }
}