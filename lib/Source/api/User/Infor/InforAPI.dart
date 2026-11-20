// Đường dẫn: lib/Source/api/User/Total/InforAPI.dart

import 'package:qlpt_frontend/Source/api/SyncedApi.dart';
import 'InforDTO.dart';

class InforAPI {
  // API lấy thông tin Profile đang đăng nhập.
  // ETag giúp không tải lại khi không đổi; email/SĐT/CCCD chỉ nằm trong RAM, không ghi xuống máy.
  static Future<UserProfileResponse> getMyProfile() async {
    try {
      return UserProfileResponse.fromJson(await SyncedApi.getJson('/api/profile/me'));
    } catch (e) {
      throw Exception(e.toString().replaceAll("Exception: ", ""));
    }
  }
}
