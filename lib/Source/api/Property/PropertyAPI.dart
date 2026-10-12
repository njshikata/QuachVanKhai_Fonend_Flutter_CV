// Đường dẫn: lib/Source/api/Property/PropertyAPI.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../API_total.dart';
import 'PropertyDTO.dart';
import '../../security/Security.dart';

class PropertyAPI {

  // Hàm gọi API lấy dữ liệu Dashboard Chủ Trọ
  static Future<List<LandlordPropertyDTO>> getDashboardData() async {
    final url = Uri.parse('${ApiTotal.baseUrl}/api/landlord/properties/dashboard');

    // 1. Mở két sắt lấy Token
    String? token = await Security.getToken();

    // Nếu không có token (chưa đăng nhập hoặc bị lỗi), trả về list rỗng hoặc ném lỗi
    if (token == null || token.isEmpty) {
      throw Exception("Lỗi Bảo Mật: Bạn chưa đăng nhập (Không tìm thấy Token)!");
    }

    try {
      // 2. Gọi API kèm Token vào Header
      final response = await http.get(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token", // Trình vé Token cho Spring Boot
        },
      );

      if (response.statusCode == 200) {
        // 3. Decode JSON và trả về dạng List<LandlordPropertyDTO>
        final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));

        return data.map((json) => LandlordPropertyDTO.fromJson(json)).toList();
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception("Phiên đăng nhập hết hạn hoặc bạn không có quyền Chủ trọ!");
      } else {
        throw Exception("Lỗi server: ${response.statusCode}");
      }
    } catch (e) {
      throw Exception("Không thể kết nối máy chủ: $e");
    }
  }
}