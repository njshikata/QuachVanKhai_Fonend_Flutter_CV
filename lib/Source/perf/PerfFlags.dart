// Đường dẫn: lib/Source/perf/PerfFlags.dart
//
// CÔNG TẮC BẬT/TẮT TỪNG KỸ THUẬT TỐI ƯU (để so sánh "trước / sau" khi demo, báo cáo).
// Các flag được đọc TRỰC TIẾP trong code thật của app (AppNetworkImage, JsonIsolate, SyncedApi, PagedListView),
// nên tắt 1 flag là toàn app chạy theo cách "chưa tối ưu" tương ứng.
// Lưu vào SharedPreferences -> tắt mở app vẫn giữ cấu hình.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PerfFlag {
  final String key;
  final String title;
  final String onText;   // Khi BẬT (đã tối ưu)
  final String offText;  // Khi TẮT (chưa tối ưu)
  final ValueNotifier<bool> notifier;

  PerfFlag(this.key, this.title, this.onText, this.offText, {bool? defaultValue})
      : defaultValue = defaultValue ?? PerfFlags.buildOptimized,
        notifier = ValueNotifier(defaultValue ?? PerfFlags.buildOptimized);

  final bool defaultValue;

  bool get value => notifier.value;
}

class PerfFlags {
  /// HAI BẢN APK: build với --dart-define=PERF_MODE=chua_toi_uu -> mặc định TẮT mọi kỹ thuật tối ưu
  /// (bản "chưa tối ưu"); không truyền / PERF_MODE=toi_uu -> mặc định BẬT hết (bản "đã tối ưu").
  /// Trong app vẫn bật/tắt từng công tắc được ở màn "Đo hiệu năng".
  static const String buildMode = String.fromEnvironment('PERF_MODE', defaultValue: 'toi_uu');
  static const bool buildOptimized = buildMode != 'chua_toi_uu';
  static String get buildLabel => buildOptimized ? 'BẢN ĐÃ TỐI ƯU' : 'BẢN CHƯA TỐI ƯU';

  // Mỗi bản lưu công tắc riêng -> cài đè bản này lên bản kia không bị lẫn cấu hình
  static const String _prefix = buildOptimized ? 'perf_flag_' : 'perf_flag_raw_';

  // ---------- Hiển thị ----------
  static final PerfFlag showOverlay = PerfFlag('overlay', 'Hiện bảng FPS / RAM',
      'Bảng đo nổi trên mọi màn hình', 'Ẩn bảng đo', defaultValue: false);

  // ---------- Các kỹ thuật tối ưu ----------
  static final PerfFlag listBuilder = PerfFlag('list_builder', 'ListView.builder (lazy render)',
      'Chỉ build các dòng đang hiện trên màn hình',
      'Column + SingleChildScrollView: build TẤT CẢ dòng 1 lúc');

  static final PerfFlag paging = PerfFlag('paging', 'Phân trang khi cuộn (ScrollController)',
      'Gần cuối danh sách mới tải trang tiếp (20 dòng/trang)',
      'Tải hết toàn bộ dữ liệu ngay từ đầu');

  static final PerfFlag imageDiskCache = PerfFlag('image_cache', 'cached_network_image (cache ảnh ra đĩa)',
      'Ảnh tải 1 lần, lần sau đọc từ bộ nhớ máy',
      'Image.network: không lưu đĩa, mở lại app là tải lại');

  static final PerfFlag imageResize = PerfFlag('image_resize', 'Ảnh thu nhỏ + memCacheWidth',
      'Xin server ảnh nhỏ (200px) và giải mã đúng kích thước hiển thị',
      'Tải + giải mã ảnh gốc 1600px vào RAM');

  static final PerfFlag isolateJson = PerfFlag('isolate_json', 'compute() parse JSON ở Isolate',
      'JSON lớn được parse ở luồng nền, UI không giật',
      'jsonDecode trên UI thread (giật khi dữ liệu lớn)');

  static final PerfFlag itemNotifier = PerfFlag('item_notifier', 'ValueNotifier cho từng item',
      'Đổi 1 dòng chỉ vẽ lại đúng dòng đó',
      'setState cả danh sách mỗi khi 1 dòng thay đổi');

  static final PerfFlag batchApi = PerfFlag('batch_api', 'Gộp request (1 API cho N phòng)',
      'Màn Dịch vụ: 1 request lấy trạng thái hóa đơn mọi phòng',
      'Gọi lần lượt 1 request cho TỪNG phòng đang thuê (N+1 request)');

  static final PerfFlag etagLocalDb = PerfFlag('etag_db', 'ETag (304) + database phụ SQLite',
      'Dữ liệu không đổi -> server trả 304, hiện ngay dữ liệu trong máy',
      'Luôn tải lại & parse lại toàn bộ JSON');

  static final List<PerfFlag> optimizations = [
    listBuilder, paging, imageDiskCache, imageResize, isolateJson, itemNotifier, batchApi, etagLocalDb,
  ];

  static final List<PerfFlag> all = [showOverlay, ...optimizations];

  /// Gộp mọi flag -> widget nào cần rebuild khi đổi flag thì lắng nghe cái này.
  static final Listenable changes = Listenable.merge(all.map((f) => f.notifier).toList());

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    for (final f in all) {
      final v = prefs.getBool('$_prefix${f.key}');
      if (v != null) f.notifier.value = v;
    }
  }

  /// Trả mọi công tắc về đúng cài đặt đã lưu (chưa lưu thì về mặc định), bỏ các thay đổi tạm thời.
  static Future<void> restoreSaved() async {
    final prefs = await SharedPreferences.getInstance();
    for (final f in all) {
      f.notifier.value = prefs.getBool('$_prefix${f.key}') ?? f.defaultValue;
    }
  }

  static Future<void> set(PerfFlag flag, bool value) async {
    flag.notifier.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefix${flag.key}', value);
  }

  static Future<void> setAllOptimizations(bool value) async {
    for (final f in optimizations) {
      await set(f, value);
    }
  }

  static bool get allOptimized => optimizations.every((f) => f.value);

  /// Mô tả ngắn cấu hình hiện tại (ghi kèm vào kết quả đo).
  static String get modeLabel {
    final off = optimizations.where((f) => !f.value).length;
    if (off == 0) return 'ĐÃ TỐI ƯU';
    if (off == optimizations.length) return 'KHÔNG TỐI ƯU';
    return 'Tắt $off/${optimizations.length} tối ưu';
  }
}
