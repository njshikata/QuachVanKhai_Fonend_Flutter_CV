// Đường dẫn: lib/Source/cache/AppCacheManager.dart
//
// 1 CacheManager dùng chung cho toàn app (ảnh thẻ, ảnh công tơ, QR...).
//  - stalePeriod 90 ngày: file nào không được dùng lại trong 3 tháng sẽ bị thư viện tự xóa.
//  - maxNrOfCacheObjects: chặn trên số file để bộ nhớ máy không phình vô hạn.
// MediaCachePolicy bổ sung luật "tính từ lúc tải về" + luật đổi chủ phòng.

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class AppCacheManager {
  static const String key = 'qlpt_media_cache';
  static const Duration maxAge = Duration(days: 90);

  static final CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: maxAge,
      maxNrOfCacheObjects: 400,
    ),
  );
}
