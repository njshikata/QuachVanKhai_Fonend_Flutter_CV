// Đường dẫn: lib/Source/api/Property/PropertyAPI.dart

import 'package:qlpt_frontend/Source/api/SyncedApi.dart';
import 'PropertyDTO.dart';

class PropertyAPI {
  static const String _dashboardPath = '/api/landlord/properties/dashboard';

  // Cùng 1 JSON (bản trong máy được dùng lại khi server trả 304) -> không dựng lại 4.000 đối tượng phòng lần 2.
  static Object? _lastJson;
  static List<LandlordPropertyDTO>? _lastParsed;

  static List<LandlordPropertyDTO> _parse(dynamic data) {
    if (_lastParsed != null && identical(data, _lastJson)) return _lastParsed!;
    final parsed = (data as List).map((json) => LandlordPropertyDTO.fromJson(json)).toList();
    _lastJson = data;
    _lastParsed = parsed;
    return parsed;
  }

  // Hàm gọi API lấy dữ liệu Dashboard Chủ Trọ (ETag: dữ liệu không đổi -> server trả 304, không tải lại)
  static Future<List<LandlordPropertyDTO>> getDashboardData() async {
    try {
      return _parse(await SyncedApi.getJson(_dashboardPath));
    } on ApiStatusException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        throw Exception("Phiên đăng nhập hết hạn hoặc bạn không có quyền Chủ trọ!");
      }
      throw Exception("Lỗi server: ${e.statusCode}");
    } catch (e) {
      throw Exception("Không thể kết nối máy chủ: $e");
    }
  }

  /// Bản lưu trong máy (có thể thiếu SĐT/email) để vẽ màn hình ngay, null nếu chưa có.
  static Future<List<LandlordPropertyDTO>?> cachedDashboard() async {
    try {
      final data = await SyncedApi.peek(_dashboardPath);
      return data == null ? null : _parse(data);
    } catch (_) {
      return null;
    }
  }
}
