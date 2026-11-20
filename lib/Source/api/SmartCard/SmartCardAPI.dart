// Đường dẫn: lib/Source/api/SmartCard/SmartCardAPI.dart
//
// API thẻ thông minh cho CHỦ TRỌ (/api/landlady/cards). Mọi thao tác chip đi qua server -> Card Bridge.
// Response được giải mã ở isolate phụ (JsonIsolate) khi lớn.

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:qlpt_frontend/Source/api/API_total.dart';
import 'package:qlpt_frontend/Source/api/JsonIsolate.dart';

import 'SmartCardDTO.dart';

/// HTTP dùng chung cho các API thẻ (chủ trọ + người thuê).
class CardHttp {
  static const Duration _timeout = Duration(seconds: 30);

  static Future<dynamic> send(String method, String path, {Object? body}) async {
    final headers = Map<String, String>.from(await ApiTotal.getAuthHeaders() as Map);
    final uri = Uri.parse('${ApiTotal.baseUrl}$path');
    final encoded = body == null ? null : jsonEncode(body);
    late http.Response res;
    switch (method) {
      case 'GET':
        res = await http.get(uri, headers: headers).timeout(_timeout);
        break;
      case 'PUT':
        res = await http.put(uri, headers: headers, body: encoded).timeout(_timeout);
        break;
      case 'DELETE':
        res = await http.delete(uri, headers: headers, body: encoded).timeout(_timeout);
        break;
      default:
        res = await http.post(uri, headers: headers, body: encoded ?? '{}').timeout(_timeout);
    }
    return handle(res.statusCode, res.bodyBytes);
  }

  static Future<dynamic> handle(int status, Uint8List bytes) async {
    if (status == 204 || bytes.isEmpty) {
      if (status >= 400) throw CardApiException(status, 'Lỗi máy chủ ($status)');
      return null;
    }
    dynamic data;
    try {
      data = await JsonIsolate.decode(bytes);
    } catch (_) {
      data = utf8.decode(bytes, allowMalformed: true); // VD: thông báo chống spam dạng text
    }
    if (status >= 200 && status < 300) return data;
    if (data is Map) {
      throw CardApiException(
        status,
        (data['message'] ?? data['error'] ?? 'Lỗi ($status)').toString(),
        pinTriesRemaining: data['pinTriesRemaining'] is int ? data['pinTriesRemaining'] as int : null,
      );
    }
    throw CardApiException(status, data.toString());
  }

  static Map<String, dynamic> map(dynamic d) => Map<String, dynamic>.from(d as Map);
}

class SmartCardAPI {
  static const String _base = '/api/landlady/cards';

  // ============================ DANH SÁCH / CHI TIẾT ============================
  static Future<PageResult<SmartCardItem>> list({int page = 0, int size = 20, String? status}) async {
    final q = 'page=$page&size=$size${status == null ? '' : '&status=$status'}';
    final data = await CardHttp.send('GET', '$_base?$q');
    return PageResult.fromJson(CardHttp.map(data), SmartCardItem.fromJson);
  }

  static Future<SmartCardDetail> detail(int id) async =>
      SmartCardDetail.fromJson(CardHttp.map(await CardHttp.send('GET', '$_base/$id')));

  static Future<PageResult<CardLogItem>> logs(int id, {int page = 0, int size = 20}) async =>
      PageResult.fromJson(CardHttp.map(await CardHttp.send('GET', '$_base/$id/logs?page=$page&size=$size')), CardLogItem.fromJson);

  static Future<PageResult<CardTransactionItem>> transactions(int id, {int page = 0, int size = 20}) async =>
      PageResult.fromJson(CardHttp.map(await CardHttp.send('GET', '$_base/$id/transactions?page=$page&size=$size')),
          CardTransactionItem.fromJson);

  // ============================ ĐẦU ĐỌC ============================
  static Future<Map<String, dynamic>> readerStatus() async => CardHttp.map(await CardHttp.send('GET', '$_base/reader'));

  /// {cardUid, registered, cardId?, status?, roomNumber?}
  static Future<Map<String, dynamic>> inspectReader() async =>
      CardHttp.map(await CardHttp.send('GET', '$_base/reader/inspect'));

  /// Chỉ dùng ở chế độ giả lập (SIM): tạo & cắm 1 thẻ trắng mới.
  static Future<Map<String, dynamic>> newBlankCard() async =>
      CardHttp.map(await CardHttp.send('POST', '$_base/reader/new-blank', body: {}));

  // ============================ CẤP / SỬA ============================
  static Future<SmartCardDetail> issue({
    required int roomId,
    required Uint8List photoBytes,
    String? holderName,
    DateTime? dateOfBirth,
    DateTime? expiryDate,
  }) async {
    final req = http.MultipartRequest('POST', Uri.parse('${ApiTotal.baseUrl}$_base/issue'));
    req.headers.addAll(await _multipartHeaders());
    req.files.add(http.MultipartFile.fromString(
      'data',
      jsonEncode({
        'roomId': roomId,
        if (holderName != null && holderName.trim().isNotEmpty) 'holderName': holderName.trim(),
        if (dateOfBirth != null) 'dateOfBirth': _iso(dateOfBirth),
        if (expiryDate != null) 'expiryDate': _iso(expiryDate),
      }),
      contentType: MediaType('application', 'json'),
    ));
    req.files.add(http.MultipartFile.fromBytes('photo', photoBytes, filename: 'photo.jpg', contentType: MediaType('image', 'jpeg')));
    return SmartCardDetail.fromJson(CardHttp.map(await _sendMultipart(req)));
  }

  static Future<SmartCardDetail> updatePhoto(int id, Uint8List photoBytes) async {
    final req = http.MultipartRequest('POST', Uri.parse('${ApiTotal.baseUrl}$_base/$id/photo'));
    req.headers.addAll(await _multipartHeaders());
    req.files.add(http.MultipartFile.fromBytes('photo', photoBytes, filename: 'photo.jpg', contentType: MediaType('image', 'jpeg')));
    return SmartCardDetail.fromJson(CardHttp.map(await _sendMultipart(req)));
  }

  static Future<SmartCardDetail> updateInfo(int id, {String? holderName, DateTime? dateOfBirth, DateTime? expiryDate}) async =>
      SmartCardDetail.fromJson(CardHttp.map(await CardHttp.send('PUT', '$_base/$id/info', body: {
        if (holderName != null) 'holderName': holderName,
        if (dateOfBirth != null) 'dateOfBirth': _iso(dateOfBirth),
        if (expiryDate != null) 'expiryDate': _iso(expiryDate),
      })));

  static Future<SmartCardItem> setStatus(int id, String status) async =>
      SmartCardItem.fromJson(CardHttp.map(await CardHttp.send('PUT', '$_base/$id/status', body: {'status': status})));

  // ============================ CHIP / PIN ============================
  static Future<CardReadResult> readCard(int id, String pin) async =>
      CardReadResult.fromJson(CardHttp.map(await CardHttp.send('POST', '$_base/$id/read', body: {'pin': pin, 'includeImage': true})));

  static Future<void> unblockPin(int id) => CardHttp.send('POST', '$_base/$id/pin/unblock');

  static Future<void> resetPin(int id) => CardHttp.send('POST', '$_base/$id/pin/reset');

  // ============================ VÍ (bắt buộc OTP gửi về điện thoại người thuê) ============================
  /// Bước 1: server gửi mã 6 số tới điện thoại người thuê. [type] = CREDIT | DEBIT.
  static Future<WalletOtpTicket> walletOtp(int id, String type, int amount) async =>
      WalletOtpTicket.fromJson(CardHttp.map(await CardHttp.send('POST', '$_base/$id/wallet/otp',
          body: {'type': type, 'amount': amount})));

  /// Bước 2 (nạp): cần mã OTP người thuê đọc lại.
  static Future<WalletResult> credit(int id, int amount,
          {required String requestId, required String otp, String? description}) async =>
      WalletResult.fromJson(CardHttp.map(await CardHttp.send('POST', '$_base/$id/credit', body: {
        'amount': amount,
        'requestId': requestId,
        'otp': otp,
        if (description != null && description.isNotEmpty) 'description': description,
      })));

  /// Bước 2 (thanh toán): cần OTP + PIN thẻ.
  static Future<WalletResult> debit(int id, int amount, String pin,
          {required String requestId, required String otp, String? description}) async =>
      WalletResult.fromJson(CardHttp.map(await CardHttp.send('POST', '$_base/$id/debit', body: {
        'amount': amount,
        'pin': pin,
        'requestId': requestId,
        'otp': otp,
        if (description != null && description.isNotEmpty) 'description': description,
      })));

  // ============================ QUẸT THẺ (chỉ cần PIN) ============================
  static Future<SwipeResult> swipe(int id, String action, String pin, {String? note}) async =>
      SwipeResult.fromJson(CardHttp.map(await CardHttp.send('POST', '$_base/$id/swipe', body: {
        'action': action,
        'pin': pin,
        'deviceId': 'APP-LANDLORD',
        if (note != null && note.isNotEmpty) 'note': note,
      })));

  // ============================ helpers ============================
  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Future<Map<String, String>> _multipartHeaders() async {
    final h = Map<String, String>.from(await ApiTotal.getAuthHeaders() as Map);
    h.remove('Content-Type'); // Để http tự đặt boundary multipart
    return h;
  }

  static Future<dynamic> _sendMultipart(http.MultipartRequest req) async {
    final streamed = await req.send().timeout(const Duration(seconds: 60));
    final res = await http.Response.fromStream(streamed);
    return CardHttp.handle(res.statusCode, res.bodyBytes);
  }
}
