// lib/Source/api/User/Pay/PayAPI.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:qlpt_frontend/Source/api/API_total.dart';
import 'PayDTO.dart';

class PayAPI {
  // Lấy mã VietQR cho một hóa đơn
  static Future<VietQRResponse> getVietQR(int invoiceId) async {
    final url = Uri.parse('${ApiTotal.baseUrl}/api/pay/vietqr/$invoiceId');

    try {
      // TỰ ĐỘNG GỘP RSA HANDSHAKE VÀ JWT TOKEN TỪ ApiTotal
      final headers = await ApiTotal.getAuthHeaders();

      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        // Decode utf8 để không bị lỗi font chữ tiếng Việt
        var jsonResponse = json.decode(utf8.decode(response.bodyBytes));
        return VietQRResponse.fromJson(jsonResponse);
      } else {
        throw Exception('Lấy mã thanh toán thất bại: ${response.body}');
      }
    } catch (e) {
      throw Exception('Không thể kết nối máy chủ: $e');
    }
  }
}