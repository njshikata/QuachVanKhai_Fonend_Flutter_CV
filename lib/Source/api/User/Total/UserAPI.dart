// Đường dẫn: lib/Source/api/User/UserAPI.dart

import 'package:qlpt_frontend/Source/api/SyncedApi.dart';
import 'UserDTO.dart';

class UserAPI {
  static const String _myRoomPath = '/api/tenant/my-room';
  static const String _myInvoicesPath = '/api/tenant/my-invoices';

  // 1. API lấy thông tin phòng đang thuê (ETag + lưu SQLite)
  static Future<MyRoomResponse> getMyRoomInfo() async {
    try {
      return MyRoomResponse.fromJson(await SyncedApi.getJson(_myRoomPath));
    } catch (e) {
      throw Exception(e.toString().replaceAll("Exception: ", ""));
    }
  }

  /// Bản lưu trong máy để vẽ ngay khi mở app, null nếu chưa có.
  static Future<MyRoomResponse?> cachedMyRoom() async {
    try {
      final data = await SyncedApi.peek(_myRoomPath);
      return data == null ? null : MyRoomResponse.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  // 2. API lấy danh sách hóa đơn (lịch sử và tháng hiện tại)
  static Future<List<MyInvoiceResponse>> getMyInvoices() async {
    try {
      final List<dynamic> jsonList = await SyncedApi.getJson(_myInvoicesPath);
      return jsonList.map((json) => MyInvoiceResponse.fromJson(json)).toList();
    } catch (e) {
      throw Exception(e.toString().replaceAll("Exception: ", ""));
    }
  }
}
