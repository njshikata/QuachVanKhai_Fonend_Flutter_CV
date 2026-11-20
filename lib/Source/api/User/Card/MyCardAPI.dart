// Đường dẫn: lib/Source/api/User/Card/MyCardAPI.dart
//
// API thẻ của NGƯỜI THUÊ (/api/tenant/card).

import 'package:qlpt_frontend/Source/api/SmartCard/SmartCardAPI.dart' show CardHttp;

import 'MyCardDTO.dart';

class MyCardAPI {
  static const String _base = '/api/tenant/card';
  static const String photoPath = '$_base/photo';

  /// null => chưa được cấp thẻ (server trả 204).
  static Future<SmartCardDetail?> myCard() async {
    final data = await CardHttp.send('GET', _base);
    return data == null ? null : SmartCardDetail.fromJson(CardHttp.map(data));
  }

  static Future<PageResult<CardLogItem>> logs({int page = 0, int size = 20}) async =>
      PageResult.fromJson(CardHttp.map(await CardHttp.send('GET', '$_base/logs?page=$page&size=$size')), CardLogItem.fromJson);

  static Future<PageResult<CardTransactionItem>> transactions({int page = 0, int size = 20}) async =>
      PageResult.fromJson(CardHttp.map(await CardHttp.send('GET', '$_base/transactions?page=$page&size=$size')),
          CardTransactionItem.fromJson);

  /// Mã xác nhận giao dịch đang chờ (nạp / thanh toán bằng thẻ).
  static Future<List<PendingOtp>> pendingOtps() async {
    final data = await CardHttp.send('GET', '$_base/otp');
    if (data is! List) return const [];
    return data.map((e) => PendingOtp.fromJson(CardHttp.map(e))).toList();
  }

  /// "Không phải tôi" – hủy yêu cầu.
  static Future<void> cancelOtp(String requestId) =>
      CardHttp.send('DELETE', '$_base/otp/${Uri.encodeComponent(requestId)}');

  /// Đổi PIN: thẻ phải đang cắm ở đầu đọc.
  static Future<void> changePin(String oldPin, String newPin) =>
      CardHttp.send('POST', '$_base/pin/change', body: {'oldPin': oldPin, 'newPin': newPin});
}
