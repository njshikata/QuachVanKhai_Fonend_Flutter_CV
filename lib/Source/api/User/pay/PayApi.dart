// lib/Source/api/User/Pay/PayAPI.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:qlpt_frontend/Source/api/API_total.dart';
import 'package:qlpt_frontend/Source/security/Security.dart';
import 'PayDTO.dart';

class PayAPI {
  // Lấy mã VietQR cho một hóa đơn
  static Future<VietQRResponse> getVietQR(int invoiceId) async {
    // ĐÃ SỬA: Đổi SecureStorage thành Security cho khớp với file Security.dart
    final token = await Security.getToken();

    if (token == null) {
      throw Exception('Không tìm thấy token. Vui lòng đăng nhập lại.');
    }

    final response = await http.get(
      Uri.parse('${ApiTotal.baseUrl}/api/pay/vietqr/$invoiceId'),
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      // Decode utf8 để không bị lỗi font chữ tiếng Việt
      var jsonResponse = json.decode(utf8.decode(response.bodyBytes));
      return VietQRResponse.fromJson(jsonResponse);
    } else {
      throw Exception('Lấy mã thanh toán thất bại: ${response.body}');
    }
  }
}