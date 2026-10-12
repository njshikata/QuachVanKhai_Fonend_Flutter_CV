// Đường dẫn: lib/Source/api/Manage/LandlordManageAPI.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:qlpt_frontend/Source/api/API_total.dart';
import 'package:qlpt_frontend/Source/security/Security.dart';
import 'LandlordManageDTO.dart';

class LandlordManageAPI {
  // Lấy Header chứa Token chuẩn
  static Future<Map<String, String>> _getHeaders() async {
    String? token = await Security.getToken();
    if (token == null || token.isEmpty) {
      throw Exception("Vui lòng đăng nhập lại!");
    }
    return {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    };
  }

  // Xử lý Response dùng chung để tránh lặp code
  static String _handleResponse(http.Response response) {
    String responseBody = utf8.decode(response.bodyBytes);
    if (response.statusCode == 200 || response.statusCode == 201) {
      return responseBody;
    } else {
      throw Exception(responseBody);
    }
  }

  // 1. Gọi API Thêm Khu trọ
  static Future<String> createProperty(CreatePropertyRequest request) async {
    // ĐÃ SỬA: /api/landlord/manage/properties
    final url = Uri.parse('${ApiTotal.baseUrl}/api/landlord/manage/properties');
    try {
      final response = await http.post(url, headers: await _getHeaders(), body: jsonEncode(request.toJson()));
      return _handleResponse(response);
    } catch (e) {
      throw Exception(e.toString().replaceAll("Exception: ", ""));
    }
  }

  // 2. Gọi API Thêm 1 Phòng
  static Future<String> createRoom(CreateRoomRequest request) async {
    // ĐÃ SỬA: /api/landlord/manage/rooms
    final url = Uri.parse('${ApiTotal.baseUrl}/api/landlord/manage/rooms');
    try {
      final response = await http.post(url, headers: await _getHeaders(), body: jsonEncode(request.toJson()));
      return _handleResponse(response);
    } catch (e) {
      throw Exception(e.toString().replaceAll("Exception: ", ""));
    }
  }

  // 3. Gọi API Thêm Khách thuê vào phòng cụ thể (Tạo hợp đồng)
  static Future<String> assignTenant(AssignTenantRequest request) async {
    // ĐÃ SỬA: /api/landlord/manage/assign-tenant (Lưu ý Backend nhận roomId qua Body JSON, không lấy từ URL nữa)
    final url = Uri.parse('${ApiTotal.baseUrl}/api/landlord/manage/assign-tenant');
    try {
      final response = await http.post(url, headers: await _getHeaders(), body: jsonEncode(request.toJson()));
      return _handleResponse(response);
    } catch (e) {
      throw Exception(e.toString().replaceAll("Exception: ", ""));
    }
  }

  // 4. Sửa thông tin Phòng
  static Future<String> updateRoom(int roomId, UpdateRoomRequest request) async {
    // ĐÃ SỬA: /api/landlord/manage/rooms/{roomId}
    final url = Uri.parse('${ApiTotal.baseUrl}/api/landlord/manage/rooms/$roomId');
    try {
      final response = await http.put(url, headers: await _getHeaders(), body: jsonEncode(request.toJson()));
      return _handleResponse(response);
    } catch (e) {
      throw Exception(e.toString().replaceAll("Exception: ", ""));
    }
  }

  // 5. Xóa Phòng
  static Future<String> deleteRoom(int roomId) async {
    // ĐÃ SỬA: /api/landlord/manage/rooms/{roomId}
    final url = Uri.parse('${ApiTotal.baseUrl}/api/landlord/manage/rooms/$roomId');
    try {
      final response = await http.delete(url, headers: await _getHeaders());
      return _handleResponse(response);
    } catch (e) {
      throw Exception(e.toString().replaceAll("Exception: ", ""));
    }
  }

  // 6. Trả phòng (Thanh lý hợp đồng)
  static Future<String> removeTenant(int roomId) async {
    final url = Uri.parse('${ApiTotal.baseUrl}/api/landlord/manage/rooms/$roomId/checkout');

    try {
      final response = await http.put(
        url,
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        // Backend đang trả về ResponseEntity.ok("Đã thanh lý hợp đồng...") dạng String
        return utf8.decode(response.bodyBytes);
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      throw Exception(e.toString().replaceAll("Exception: ", ""));
    }
  }

}