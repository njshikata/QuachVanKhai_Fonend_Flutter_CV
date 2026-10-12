// Đường dẫn: lib/Source/api/ServiceRoom/ServiceRoomAPI.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qlpt_frontend/Source/api/API_total.dart';
import 'package:qlpt_frontend/Source/security/Security.dart';
import 'ServiceRoomDTO.dart';

class ServiceRoomAPI {
  static String get baseUrl => '${ApiTotal.baseUrl}/api/landlord/room-services';

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

  static Future<List<CatalogResponse>> getCatalog() async {
    final url = Uri.parse('$baseUrl/catalog');
    try {
      final response = await http.get(url, headers: await _getHeaders());
      if (response.statusCode == 200) {
        List<dynamic> jsonList = jsonDecode(utf8.decode(response.bodyBytes));
        return jsonList.map((json) => CatalogResponse.fromJson(json)).toList();
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      throw Exception(e.toString().replaceAll("Exception: ", ""));
    }
  }

  static Future<RoomBillingSummary> getRoomBillingSummary(int roomId) async {
    final url = Uri.parse('$baseUrl/room/$roomId');
    try {
      final response = await http.get(url, headers: await _getHeaders());
      if (response.statusCode == 200) {
        return RoomBillingSummary.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      throw Exception(e.toString().replaceAll("Exception: ", ""));
    }
  }

  // --- MỚI THÊM: Lấy Lịch sử Hóa Đơn ---
  static Future<List<InvoiceHistoryResponse>> getInvoiceHistory(int roomId) async {
    final url = Uri.parse('$baseUrl/room/$roomId/history');
    try {
      final response = await http.get(url, headers: await _getHeaders());
      if (response.statusCode == 200) {
        List<dynamic> jsonList = jsonDecode(utf8.decode(response.bodyBytes));
        return jsonList.map((json) => InvoiceHistoryResponse.fromJson(json)).toList();
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      throw Exception(e.toString().replaceAll("Exception: ", ""));
    }
  }

  // --- MỚI THÊM: Xác nhận thu tiền mặt ---
  static Future<String> confirmCashPayment(int invoiceId) async {
    final url = Uri.parse('$baseUrl/invoice/$invoiceId/pay-cash');
    try {
      final response = await http.put(url, headers: await _getHeaders());
      if (response.statusCode == 200) {
        return utf8.decode(response.bodyBytes);
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      throw Exception(e.toString().replaceAll("Exception: ", ""));
    }
  }

  static Future<String> assignService(int roomId, AssignRequest request) async {
    final url = Uri.parse('$baseUrl/room/$roomId');
    try {
      final response = await http.post(
        url,
        headers: await _getHeaders(),
        body: jsonEncode(request.toJson()),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return utf8.decode(response.bodyBytes);
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      throw Exception(e.toString().replaceAll("Exception: ", ""));
    }
  }

  static Future<String> updateCustomPrice(int roomServiceId, double? customPrice) async {
    String queryParam = customPrice != null ? '?customPrice=$customPrice' : '';
    final url = Uri.parse('$baseUrl/$roomServiceId/price$queryParam');

    try {
      final response = await http.put(url, headers: await _getHeaders());
      if (response.statusCode == 200) {
        return utf8.decode(response.bodyBytes);
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      throw Exception(e.toString().replaceAll("Exception: ", ""));
    }
  }

  static Future<String> removeService(int roomServiceId) async {
    final url = Uri.parse('$baseUrl/$roomServiceId');
    try {
      final response = await http.delete(url, headers: await _getHeaders());
      if (response.statusCode == 200) {
        return utf8.decode(response.bodyBytes);
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      throw Exception(e.toString().replaceAll("Exception: ", ""));
    }
  }

  static Future<UtilityReadingResponse> recordUtility(int roomId, RecordUtilityRequest requestData, XFile imageFile) async {
    String? token = await Security.getToken();
    var uri = Uri.parse('$baseUrl/room/$roomId/record-utility');

    var request = http.MultipartRequest('POST', uri);

    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    request.headers['Accept'] = 'application/json';

    request.files.add(
      http.MultipartFile.fromString(
        'data',
        jsonEncode(requestData.toJson()),
        contentType: MediaType('application', 'json', {'charset': 'utf-8'}),
      ),
    );

    var bytes = await imageFile.readAsBytes();
    var multipartFile = http.MultipartFile.fromBytes(
        'image',
        bytes,
        filename: imageFile.name.isEmpty ? 'image.jpg' : imageFile.name
    );

    request.files.add(multipartFile);

    try {
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return UtilityReadingResponse.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      throw Exception("Lỗi chốt số: ${e.toString().replaceAll("Exception: ", "")}");
    }
  }
}