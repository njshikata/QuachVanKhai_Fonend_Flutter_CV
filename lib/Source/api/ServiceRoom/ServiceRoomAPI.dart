// Đường dẫn: lib/Source/api/ServiceRoom/ServiceRoomAPI.dart

import 'package:qlpt_frontend/Source/api/JsonIsolate.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qlpt_frontend/Source/api/API_total.dart';
import 'package:qlpt_frontend/Source/api/SyncedApi.dart';
import 'ServiceRoomDTO.dart';

class ServiceRoomAPI {
  static String get baseUrl => '${ApiTotal.baseUrl}/api/landlord/room-services';

  // SỬ DỤNG HÀM TỔNG TỪ ApiTotal ĐỂ TỰ ĐỘNG CÓ RSA HANDSHAKE VÀ TOKEN
  static Future _getHeaders() async {
    return await ApiTotal.getAuthHeaders();
  }

  // 3 API đọc dưới đây dùng ETag (304 khi không đổi) + database phụ
  static const String _path = '/api/landlord/room-services';

  static Future<List<CatalogResponse>> getCatalog() async {
    try {
      final List<dynamic> jsonList = await SyncedApi.getJson('$_path/catalog');
      return jsonList.map((json) => CatalogResponse.fromJson(json)).toList();
    } catch (e) {
      throw Exception(e.toString().replaceAll("Exception: ", ""));
    }
  }

  /// Trạng thái hóa đơn của MỌI phòng đang thuê trong 1 request (Map roomId -> summary rút gọn).
  static Future<Map<int, RoomBillingSummary>> getAllBillingStatus() async {
    try {
      final List<dynamic> list = await SyncedApi.getJson('$_path/billing-status');
      final map = <int, RoomBillingSummary>{};
      for (final j in list) {
        final s = RoomBillingSummary.fromJson(Map<String, dynamic>.from(j as Map));
        map[s.roomId] = s;
      }
      return map;
    } catch (e) {
      throw Exception(e.toString().replaceAll("Exception: ", ""));
    }
  }

  /// Bản trạng thái hóa đơn lưu trong máy (SQLite/RAM) để vẽ màn hình ngay, null nếu chưa có.
  static Future<Map<int, RoomBillingSummary>?> cachedBillingStatus() async {
    try {
      final list = await SyncedApi.peek('$_path/billing-status');
      if (list == null) return null;
      final map = <int, RoomBillingSummary>{};
      for (final j in list as List) {
        final s = RoomBillingSummary.fromJson(Map<String, dynamic>.from(j as Map));
        map[s.roomId] = s;
      }
      return map;
    } catch (_) {
      return null;
    }
  }

  static Future<RoomBillingSummary> getRoomBillingSummary(int roomId) async {
    try {
      return RoomBillingSummary.fromJson(await SyncedApi.getJson('$_path/room/$roomId'));
    } catch (e) {
      throw Exception(e.toString().replaceAll("Exception: ", ""));
    }
  }

  // --- Lấy Lịch sử Hóa Đơn ---
  static Future<List<InvoiceHistoryResponse>> getInvoiceHistory(int roomId) async {
    try {
      final List<dynamic> jsonList = await SyncedApi.getJson('$_path/room/$roomId/history');
      return jsonList.map((json) => InvoiceHistoryResponse.fromJson(json)).toList();
    } catch (e) {
      throw Exception(e.toString().replaceAll("Exception: ", ""));
    }
  }

  // --- Xác nhận thu tiền mặt ---
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
    var uri = Uri.parse('$baseUrl/room/$roomId/record-utility');

    var request = http.MultipartRequest('POST', uri);

    // LẤY TOÀN BỘ HEADERS BẢO MẬT (RSA PAYLOAD + JWT TOKEN) TỪ ApiTotal
    Map<String, String> authHeaders = await ApiTotal.getAuthHeaders();
    request.headers.addAll(authHeaders);
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
        return UtilityReadingResponse.fromJson(await JsonIsolate.decode(response.bodyBytes));
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      throw Exception("Lỗi chốt số: ${e.toString().replaceAll("Exception: ", "")}");
    }
  }
}