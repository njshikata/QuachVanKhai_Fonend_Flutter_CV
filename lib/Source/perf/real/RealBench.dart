// Đường dẫn: lib/Source/perf/real/RealBench.dart
//
// ============================================================================================
//  ĐO TRÊN APP THẬT – DỮ LIỆU THẬT (đề tài: Tối ưu hóa bộ nhớ và giao diện khi xử lý dữ liệu trên di động)
// ============================================================================================
//
// Đo trên CHÍNH các màn hình của app (Nhà trọ, Dịch vụ, Người dùng, Thẻ), gọi API thật,
// đọc dữ liệu thật trong database PostgreSQL. Không dùng danh sách giả lập.
//
// Có 2 cách đo, kết quả lưu chung một chỗ để vẽ biểu đồ so sánh:
//   1. TỰ ĐỘNG  (RealBench.runAuto): với mỗi màn hình chạy 2 lượt, lượt "ĐÃ tối ưu" rồi lượt "CHƯA tối ưu".
//      Mỗi lượt: xóa cache -> mở màn hình thật -> đo thời gian tới khi danh sách hiện -> tự cuộn N giây.
//      Trong suốt lượt, PerfMonitor ghi mỗi giây 1 mẫu: FPS, khung hình giật, RAM (RSS), RAM ảnh, dữ liệu mạng.
//   2. THỦ CÔNG (RealBench.startManual): người test tự chọn chế độ, tự mở và tự thao tác trên app.
//      Bấm ■ STOP trên bảng FPS để kết thúc; phiên ghi được lưu như một lần đo.
//      Bấm ● REC trực tiếp trên bảng FPS ở bất kỳ đâu trong app cũng được lưu, dưới tên "Ghi tự do".
//
// Vì sao lượt ĐÃ tối ưu chạy trước: lượt CHƯA tối ưu bắn rất nhiều request và chiếm nhiều RAM.
// Chạy nó trước thì lượt sau bị ảnh hưởng (mạng còn nghẽn, GC chưa dọn), số liệu không công bằng.
//
// Chỉ giữ kết quả của lần đo MỚI NHẤT (không có lịch sử). Vẫn ghi vào SharedPreferences vì bài
// "tắt hẳn app rồi bật lại" cần giữ kết quả qua các lần app bị kill.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qlpt_frontend/Source/api/SyncedApi.dart';
import 'package:qlpt_frontend/Source/scr/HomePage/landlady/ServiceRoom/ServiceRoomScreen.dart';
import 'package:qlpt_frontend/Source/scr/HomePage/landlady/SmartCard/SmartCardScreen.dart';
import 'package:qlpt_frontend/Source/scr/HomePage/landlady/Tab/TabUser/Manage_User_Screen.dart';
import 'package:qlpt_frontend/Source/scr/HomePage/landlady/Tab/room/Dashboard_Properti_Screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../PerfFlags.dart';
import 'BenchAnalysis.dart';
import '../PerfMonitor.dart';

// ============================================================================================
// CÁC MÀN HÌNH THẬT ĐƯỢC ĐO
// ============================================================================================

class RealScreen {
  final String id;
  final String name;
  final String techniques; // Kỹ thuật tối ưu tác động lên màn này
  final Widget Function() build;

  const RealScreen(this.id, this.name, this.techniques, this.build);
}

final List<RealScreen> realScreens = [
  RealScreen('dashboard', 'Nhà trọ (khu trọ + phòng)', 'ListView.builder phẳng, compute() JSON, ETag/SQLite',
      () => const DashboardPropertiScreen()),
  RealScreen('service', 'Dịch vụ (phòng + trạng thái hóa đơn)', 'SliverList.builder, gộp request, compute() JSON, ETag/SQLite',
      () => const ServiceRoomScreen()),
  RealScreen('users', 'Người dùng (khách thuê)', 'ListView.builder, compute() JSON, ETag/SQLite',
      () => const ManageUserScreen()),
  RealScreen('cards', 'Thẻ cư dân (ảnh thẻ)', 'ListView.builder + ScrollController phân trang, ValueNotifier, '
      'cached_network_image + memCacheWidth', () => const SmartCardScreen()),
];

// ============================================================================================
// 1 LẦN ĐO
// ============================================================================================

/// Chế độ của 1 lần đo, xác định từ trạng thái các công tắc lúc đo.
enum BenchMode {
  before('CHƯA tối ưu'),
  after('ĐÃ tối ưu'),
  mixed('Tùy chỉnh');

  final String label;

  const BenchMode(this.label);

  static BenchMode current() {
    final on = PerfFlags.optimizations.where((f) => f.value).length;
    if (on == PerfFlags.optimizations.length) return after;
    if (on == 0) return before;
    return mixed;
  }
}

class BenchRun {
  final String screen; // Tên màn hình (hoặc "Ghi tự do")
  final BenchMode mode;
  final bool auto; // true = tự động, false = thủ công
  final DateTime at;
  final String build; // Bản APK đo: "BẢN ĐÃ TỐI ƯU" / "BẢN CHƯA TỐI ƯU"
  final int? openMs; // Thời gian từ lúc mở màn tới khi danh sách hiện (null nếu không đo được)
  // Chỉ có ở bài "tắt hẳn app rồi bật lại": thời gian từ lúc bấm tới khi app vẽ xong khung hình đầu tiên.
  // Khi đó openMs = từ lúc bấm (app đang chạy) tới khi màn hình hiện dữ liệu, gồm cả thời gian khởi động app.
  final int? bootMs;
  final double avgFps, minFps, jankPct, worstMs, avgRss, maxRss, maxImageMb, netKb;
  final int netRequests, itemBuilds, seconds;
  // Chuỗi theo thời gian (mỗi giây 1 điểm) để vẽ biểu đồ đường
  final List<double> fpsSeries, rssSeries, imageSeries;

  BenchRun({
    required this.screen,
    required this.mode,
    required this.auto,
    required this.at,
    required this.build,
    required this.openMs,
    this.bootMs,
    required this.avgFps,
    required this.minFps,
    required this.jankPct,
    required this.worstMs,
    required this.avgRss,
    required this.maxRss,
    required this.maxImageMb,
    required this.netKb,
    required this.netRequests,
    required this.itemBuilds,
    required this.seconds,
    required this.fpsSeries,
    required this.rssSeries,
    required this.imageSeries,
  });

  /// [totals] = true khi bộ đếm đã reset về 0 lúc bắt đầu đo (_coldStart): lấy thẳng TỔNG của bộ đếm.
  /// Lý do: mạng LAN nhanh, request thường xong TRƯỚC mẫu đo đầu tiên (mẫu lấy mỗi giây), nên lấy chênh lệch
  /// giữa mẫu cuối và mẫu đầu sẽ ra 0 KB / 0 dòng, sai.
  factory BenchRun.fromReport(PerfReport r,
          {required String screen, required bool auto, int? openMs, int? bootMs, BenchMode? mode, bool totals = false}) =>
      BenchRun(
        screen: screen,
        mode: mode ?? BenchMode.current(),
        auto: auto,
        at: DateTime.now(),
        build: PerfFlags.buildLabel,
        openMs: openMs,
        bootMs: bootMs,
        avgFps: r.avgFps,
        minFps: r.minFps,
        jankPct: r.jankPercent,
        worstMs: r.worstMs,
        avgRss: r.avgRss,
        maxRss: r.maxRss,
        maxImageMb: r.maxImageMb,
        netKb: totals ? SyncedApi.stats.bytesDownloaded / 1024 : r.netKb,
        netRequests: totals ? SyncedApi.stats.requests : r.netRequests,
        itemBuilds: totals ? PerfCounters.itemBuilds : r.itemBuilds,
        seconds: r.duration.inSeconds,
        fpsSeries: [for (final s in r.samples) s.fps],
        rssSeries: [for (final s in r.samples) s.rssMb < 0 ? 0 : s.rssMb],
        imageSeries: [for (final s in r.samples) s.imageCacheMb],
      );

  Map<String, dynamic> toJson() => {
        'screen': screen,
        'mode': mode.name,
        'auto': auto,
        'at': at.toIso8601String(),
        'build': build,
        'openMs': openMs,
        if (bootMs != null) 'bootMs': bootMs,
        'avgFps': avgFps,
        'minFps': minFps,
        'jankPct': jankPct,
        'worstMs': worstMs,
        'avgRss': avgRss,
        'maxRss': maxRss,
        'maxImageMb': maxImageMb,
        'netKb': netKb,
        'netRequests': netRequests,
        'itemBuilds': itemBuilds,
        'seconds': seconds,
        'fps': [for (final v in fpsSeries) double.parse(v.toStringAsFixed(1))],
        'rss': [for (final v in rssSeries) double.parse(v.toStringAsFixed(1))],
        'img': [for (final v in imageSeries) double.parse(v.toStringAsFixed(1))],
      };

  static double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;
  static List<double> _l(dynamic v) => [for (final x in (v as List? ?? const [])) _d(x)];

  factory BenchRun.fromJson(Map<String, dynamic> j) => BenchRun(
        screen: j['screen'] as String,
        mode: BenchMode.values.byName(j['mode'] as String),
        auto: j['auto'] == true,
        at: DateTime.parse(j['at'] as String),
        build: j['build'] as String? ?? '',
        openMs: (j['openMs'] as num?)?.toInt(),
        bootMs: (j['bootMs'] as num?)?.toInt(),
        avgFps: _d(j['avgFps']),
        minFps: _d(j['minFps']),
        jankPct: _d(j['jankPct']),
        worstMs: _d(j['worstMs']),
        avgRss: _d(j['avgRss']),
        maxRss: _d(j['maxRss']),
        maxImageMb: _d(j['maxImageMb']),
        netKb: _d(j['netKb']),
        netRequests: (j['netRequests'] as num?)?.toInt() ?? 0,
        itemBuilds: (j['itemBuilds'] as num?)?.toInt() ?? 0,
        seconds: (j['seconds'] as num?)?.toInt() ?? 0,
        fpsSeries: _l(j['fps']),
        rssSeries: _l(j['rss']),
        imageSeries: _l(j['img']),
      );

  String get sourceLabel => bootMs != null ? 'Tắt/bật app' : (auto ? 'Tự động' : 'Thủ công');
}

/// 1 chỉ số so sánh giữa 2 lần đo (dùng cho bảng + biểu đồ cột).
class CompareMetric {
  final String name;
  final String unit;
  final double before;
  final double after;
  final bool lowerIsBetter;
  final int decimals;

  const CompareMetric(this.name, this.unit, this.before, this.after, {this.lowerIsBetter = true, this.decimals = 0});

  String fmt(double v) => '${v.toStringAsFixed(decimals)}${unit.isEmpty ? '' : ' $unit'}';

  /// Hệ số cải thiện (>1 = tốt hơn)
  double? get gain {
    if (lowerIsBetter) return after <= 0 ? (before > 0 ? double.infinity : null) : before / after;
    return before <= 0 ? (after > 0 ? double.infinity : null) : after / before;
  }

  String get gainStr {
    final g = gain;
    if (g == null) return '–';
    if (g.isInfinite) return 'giảm về 0';
    if (g == 0) return 'kém hơn (từ 0)';
    if (g >= 1.1) return 'tốt hơn ×${g.toStringAsFixed(g >= 10 ? 0 : 1)}';
    if (g <= 0.9) return 'kém hơn ×${(1 / g).toStringAsFixed(1)}';
    return 'tương đương';
  }

  bool get better => (gain ?? 1) >= 1.1;
}

/// Cặp CHƯA tối ưu / ĐÃ tối ưu (lần đo mới nhất mỗi chế độ) của 1 màn hình.
class BenchPair {
  final String screen;
  final BenchRun? before;
  final BenchRun? after;

  const BenchPair(this.screen, this.before, this.after);

  bool get complete => before != null && after != null;

  List<CompareMetric> get metrics {
    final b = before!, a = after!;
    return [
      // TỐC ĐỘ đứng đầu (ưu tiên số 1), sau đó mới tới bộ nhớ
      if (b.bootMs != null && a.bootMs != null)
        CompareMetric('Bật lại app tới khung hình đầu', 'ms', b.bootMs!.toDouble(), a.bootMs!.toDouble()),
      if (b.openMs != null && a.openMs != null)
        CompareMetric(b.bootMs != null ? 'Tắt/bật app tới khi THẤY DỮ LIỆU' : 'Thời gian mở màn hình', 'ms',
            b.openMs!.toDouble(), a.openMs!.toDouble()),
      CompareMetric('Khung hình chậm nhất (đứng hình)', 'ms', b.worstMs, a.worstMs),
      CompareMetric('FPS trung bình', '', b.avgFps, a.avgFps, lowerIsBetter: false),
      CompareMetric('FPS thấp nhất', '', b.minFps, a.minFps, lowerIsBetter: false),
      CompareMetric('Khung hình giật', '%', b.jankPct, a.jankPct, decimals: 1),
      CompareMetric('RAM cao nhất (RSS)', 'MB', b.maxRss, a.maxRss),
      CompareMetric('RAM trung bình', 'MB', b.avgRss, a.avgRss),
      CompareMetric('RAM ảnh cao nhất', 'MB', b.maxImageMb, a.maxImageMb, decimals: 1),
      CompareMetric('Dữ liệu tải qua mạng', 'KB', b.netKb, a.netKb),
      CompareMetric('Số dòng phải build', '', b.itemBuilds.toDouble(), a.itemBuilds.toDouble()),
    ];
  }
}

// ============================================================================================
// LƯU TRỮ + CHẠY ĐO
// ============================================================================================

class RealBench {
  static const String _key = 'real_bench_runs_v1';
  static const int _maxRuns = 120;

  /// Danh sách các lần đo, mới nhất ở đầu. Lắng nghe để vẽ lại biểu đồ.
  static final ValueNotifier<List<BenchRun>> runs = ValueNotifier(const []);

  /// Trạng thái khi đang chạy tự động (null = không chạy)
  static final ValueNotifier<String?> status = ValueNotifier(null);

  static bool _autoRunning = false;

  /// true khi bài đo khác (tắt/bật app) đang tự ghi và tự lưu kết quả -> bộ ghi thủ công bỏ qua, tránh lưu trùng.
  static bool externalRecording = false;
  static bool _cancel = false;
  static String? _manualScreen; // Màn hình đang ghi thủ công
  static int? _manualOpenMs;
  static bool _inited = false;

  static Future<void> init() async {
    if (_inited) return;
    _inited = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) {
        runs.value = [for (final j in jsonDecode(raw) as List) BenchRun.fromJson(Map<String, dynamic>.from(j as Map))];
      }
    } catch (_) {}
    // Mọi phiên ghi (nút ● REC trên bảng FPS) không phải do chạy tự động -> lưu thành lần đo thủ công
    PerfMonitor.instance.reportListeners.add((r) {
      if (_autoRunning || externalRecording) return;
      final screen = _manualScreen ?? 'Ghi tự do';
      final openMs = _manualOpenMs;
      _manualScreen = null;
      _manualOpenMs = null;
      if (r.samples.length < 2) return;
      final totals = _countersReset;
      _countersReset = false;
      add(BenchRun.fromReport(r, screen: screen, auto: false, openMs: openMs, totals: totals));
    });
  }

  /// CHỈ GIỮ KẾT QUẢ MỚI NHẤT (không lưu lịch sử):
  ///  - [session] = true (đang chạy tự động nhiều màn): bản mới thay bản cũ cùng màn + cùng chế độ,
  ///    các màn khác của CÙNG lượt chạy giữ lại (lượt chạy tự động đã xóa sạch kết quả cũ lúc bắt đầu).
  ///  - [session] = false (đo thủ công 1 màn): chỉ giữ cặp của màn này, mọi kết quả cũ khác bị ẩn.
  static Future<void> add(BenchRun r, {bool session = false}) async {
    final keep = session
        ? runs.value.where((x) => !(x.screen == r.screen && x.mode == r.mode))
        : runs.value.where((x) => x.screen == r.screen && x.mode != r.mode);
    runs.value = [r, ...keep];
    await _save();
  }

  static Future<void> remove(BenchRun r) async {
    runs.value = runs.value.where((x) => !identical(x, r)).toList();
    await _save();
  }

  static Future<void> clear() async {
    runs.value = const [];
    await _save();
  }

  static Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode([for (final r in runs.value) r.toJson()]));
  }

  /// Xuất toàn bộ kết quả (JSON) để nhập vào máy khác.
  static String exportJson() => jsonEncode([for (final r in runs.value) r.toJson()]);

  /// Nhập kết quả từ máy khác (gộp, bỏ trùng). Trả về số lần đo được thêm.
  static Future<int> importJson(String raw) async {
    final list = [for (final j in jsonDecode(raw.trim()) as List) BenchRun.fromJson(Map<String, dynamic>.from(j as Map))];
    final have = {for (final r in runs.value) '${r.screen}|${r.at.toIso8601String()}'};
    final added = list.where((r) => !have.contains('${r.screen}|${r.at.toIso8601String()}')).toList();
    final all = [...runs.value, ...added]..sort((a, b) => b.at.compareTo(a.at));
    runs.value = all.take(_maxRuns).toList();
    await _save();
    return added.length;
  }

  /// Cặp so sánh mới nhất cho từng màn hình (theo thứ tự realScreens, rồi các tên khác).
  static List<BenchPair> pairs() {
    // Kết quả "tắt/bật app" (trực quan nhất) lên đầu, sau đó các màn đo trong app
    final names = <String>[...realScreens.map((s) => '${s.name} · tắt/bật app'), ...realScreens.map((s) => s.name)];
    for (final r in runs.value) {
      if (!names.contains(r.screen)) names.add(r.screen);
    }
    final out = <BenchPair>[];
    for (final n in names) {
      BenchRun? b, a;
      for (final r in runs.value) {
        if (r.screen != n) continue;
        if (r.mode == BenchMode.before) b ??= r;
        if (r.mode == BenchMode.after) a ??= r;
      }
      if (b != null || a != null) out.add(BenchPair(n, b, a));
    }
    return out;
  }

  static void cancel() => _cancel = true;

  // ------------------------------------------------------------------------------------------
  // ĐO TỰ ĐỘNG
  // ------------------------------------------------------------------------------------------

  /// Chạy đo tự động trên [screens], mỗi màn 2 lượt (ĐÃ tối ưu, rồi CHƯA tối ưu).
  /// Công tắc chỉ đổi tạm (không lưu), xong trả lại như cũ.
  static Future<void> runAuto(NavigatorState nav, List<RealScreen> screens, {int scrollSeconds = 10}) async {
    if (_autoRunning) return;
    _autoRunning = true;
    await clear(); // lượt đo mới: ẩn toàn bộ kết quả cũ
    _cancel = false;
    final saved = {for (final f in PerfFlags.all) f: f.value};
    PerfFlags.showOverlay.notifier.value = true; // Hiện bảng FPS/RAM trong lúc đo để người xem thấy
    try {
      for (final screen in screens) {
        // LƯỢT KHỞI ĐỘNG (không tính điểm): mở màn 1 lần ở mỗi chế độ để code Dart / shader đã sẵn sàng.
        // Không có bước này, lượt đo đầu tiên luôn chậm hơn vì máy vừa mới chạy, so sánh sẽ không công bằng.
        for (final optimized in [true, false]) {
          if (_cancel) return;
          for (final f in PerfFlags.optimizations) {
            f.notifier.value = optimized;
          }
          status.value = '${screen.name}: lượt khởi động (không tính điểm)...';
          await _coldStart();
          await _warmUp(nav, screen);
        }
        for (final optimized in [true, false]) {
          if (_cancel) return;
          for (final f in PerfFlags.optimizations) {
            f.notifier.value = optimized;
          }
          final mode = optimized ? BenchMode.after : BenchMode.before;
          status.value = '${screen.name} – ${mode.label}: đang chuẩn bị...';
          await _coldStart();
          final run = await _measureOnce(nav, screen, mode, scrollSeconds);
          if (run != null) await add(run, session: true);
        }
      }
    } finally {
      for (final e in saved.entries) {
        e.key.notifier.value = e.value;
      }
      _autoRunning = false;
      status.value = null;
    }
  }

  /// Xóa cache trong RAM để 2 lượt bắt đầu như nhau (dữ liệu phải tải lại từ server).
  /// Không xóa ảnh trên đĩa: người dùng thật mở app lần 2 vẫn có sẵn ảnh, đó chính là tác dụng của cache.
  static Future<void> _coldStart() async {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    await SyncedApi.clear();
    SyncedApi.stats.reset();
    PerfCounters.itemBuilds = 0;
    _countersReset = true;
    await Future<void>.delayed(const Duration(seconds: 2)); // Cho GC dọn rác của lượt trước
  }

  /// true = bộ đếm mạng / số dòng build vừa được reset bởi _coldStart (dùng tổng thay vì chênh lệch mẫu).
  static bool _countersReset = false;

  static Future<void> _warmUp(NavigatorState nav, RealScreen screen) async {
    final key = GlobalKey();
    final route = MaterialPageRoute<void>(builder: (_) => KeyedSubtree(key: key, child: screen.build()));
    unawaited(nav.push(route));
    try {
      final pos = await waitForContent(key, timeout: const Duration(seconds: 120));
      await autoScroll(pos, const Duration(seconds: 2));
    } catch (_) {
    } finally {
      if (route.isActive) nav.removeRoute(route);
    }
  }

  static Future<BenchRun?> _measureOnce(NavigatorState nav, RealScreen screen, BenchMode mode, int scrollSeconds) async {
    final key = GlobalKey();
    PerfMonitor.instance.startRecording('${screen.name} [${mode.label}]');
    final sw = Stopwatch()..start();
    final route = MaterialPageRoute<void>(builder: (_) => KeyedSubtree(key: key, child: screen.build()));
    unawaited(nav.push(route));
    int? openMs;
    try {
      status.value = '${screen.name} – ${mode.label}: đang tải dữ liệu thật...';
      final pos = await waitForContent(key, timeout: const Duration(seconds: 120));
      openMs = sw.elapsedMilliseconds;
      await Future<void>.delayed(const Duration(milliseconds: 700));
      status.value = '${screen.name} – ${mode.label}: mở sau $openMs ms, đang tự cuộn ${scrollSeconds}s...';
      await autoScroll(pos, Duration(seconds: scrollSeconds));
      await Future<void>.delayed(const Duration(milliseconds: 1200)); // Lấy nốt mẫu cuối
    } catch (e) {
      status.value = '${screen.name} – ${mode.label}: lỗi $e';
      await Future<void>.delayed(const Duration(seconds: 2));
    } finally {
      if (route.isActive) nav.removeRoute(route);
    }
    final report = PerfMonitor.instance.stopRecording();
    if (report == null) return null;
    return BenchRun.fromReport(report, screen: screen.name, auto: true, openMs: openMs, mode: mode, totals: true);
  }

  // ------------------------------------------------------------------------------------------
  // ĐO THỦ CÔNG
  // ------------------------------------------------------------------------------------------

  /// Bắt đầu ghi thủ công: bật bảng FPS, ghi số liệu, mở màn [screen] (null = người test tự đi trong app).
  /// Kết thúc bằng nút ■ STOP trên bảng FPS.
  static Future<void> startManual(NavigatorState nav, RealScreen? screen) async {
    PerfFlags.showOverlay.notifier.value = true;
    await _coldStart();
    _manualScreen = screen?.name ?? 'Ghi tự do';
    _manualOpenMs = null;
    PerfMonitor.instance.startRecording('${_manualScreen!} [${BenchMode.current().label}] thủ công');
    if (screen == null) return;
    final key = GlobalKey();
    final sw = Stopwatch()..start();
    unawaited(nav.push(MaterialPageRoute<void>(builder: (_) => KeyedSubtree(key: key, child: screen.build()))));
    try {
      await waitForContent(key, timeout: const Duration(seconds: 120));
      if (PerfMonitor.instance.recording.value) _manualOpenMs = sw.elapsedMilliseconds;
    } catch (_) {}
  }

  // ------------------------------------------------------------------------------------------
  // TIỆN ÍCH
  // ------------------------------------------------------------------------------------------

  /// Đợi tới khi màn hình có danh sách cuộn được (dữ liệu đã hiện), trả về vị trí cuộn của danh sách chính.
  static Future<ScrollPosition> waitForContent(GlobalKey key, {required Duration timeout}) async {
    final sw = Stopwatch()..start();
    while (true) {
      final pos = mainScroll(key.currentContext);
      if (pos != null && pos.maxScrollExtent > 0) return pos;
      if (sw.elapsed > timeout) throw TimeoutException('Quá ${timeout.inSeconds}s mà danh sách chưa hiện');
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  /// Danh sách cuộn dọc dài nhất trong màn hình (danh sách chính).
  static ScrollPosition? mainScroll(BuildContext? context) {
    if (context == null) return null;
    ScrollPosition? best;
    void visit(Element e) {
      if (e is StatefulElement && e.state is ScrollableState) {
        final st = e.state as ScrollableState;
        final p = st.position;
        if (p.axis == Axis.vertical && p.hasContentDimensions && (best == null || p.maxScrollExtent > best!.maxScrollExtent)) {
          best = p;
        }
      }
      e.visitChildElements(visit);
    }

    (context as Element).visitChildElements(visit);
    return best;
  }

  /// Tự cuộn đều ~2400 px/giây như người dùng vuốt liên tục; hết danh sách thì quay về đầu.
  static Future<void> autoScroll(ScrollPosition pos, Duration duration) async {
    final sw = Stopwatch()..start();
    while (sw.elapsed < duration && !_cancel) {
      final max = pos.maxScrollExtent;
      final target = pos.pixels + 1200;
      if (target >= max) {
        if (max > pos.pixels) await pos.animateTo(max, duration: const Duration(milliseconds: 250), curve: Curves.linear);
        // Danh sách phân trang: đợi trang kế tiếp về (maxScrollExtent tăng), quá 1,5s thì quay về đầu
        final wait = Stopwatch()..start();
        while (pos.maxScrollExtent <= max && wait.elapsedMilliseconds < 1500) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        if (pos.maxScrollExtent <= max) pos.jumpTo(0);
        continue;
      }
      await pos.animateTo(target, duration: const Duration(milliseconds: 500), curve: Curves.linear);
    }
  }

  /// Bảng Markdown toàn bộ kết quả (dán vào báo cáo).
  static String markdown() {
    final b = StringBuffer('## So sánh trên app thật – dữ liệu thật\n\n');
    for (final p in pairs()) {
      b.writeln('### ${p.screen}\n');
      if (!p.complete) {
        b.writeln('_Chưa đủ 2 chế độ (${p.before == null ? 'thiếu CHƯA tối ưu' : 'thiếu ĐÃ tối ưu'})_\n');
        continue;
      }
      b.writeln('Đo: CHƯA tối ưu ${p.before!.sourceLabel} ${_t(p.before!.at)} · ĐÃ tối ưu ${p.after!.sourceLabel} ${_t(p.after!.at)}\n');
      b.writeln('| Chỉ số | Chưa tối ưu | Đã tối ưu | Kết quả |');
      b.writeln('|---|---|---|---|');
      for (final m in p.metrics) {
        b.writeln('| ${m.name} | ${m.fmt(m.before)} | ${m.fmt(m.after)} | ${m.gainStr} |');
      }
      b.writeln();
      b.writeln(BenchAnalysis.markdown(p));
    }
    return b.toString();
  }

  /// CSV chuỗi theo thời gian (FPS, RAM) để vẽ lại biểu đồ trong Excel.
  static String csv() {
    final b = StringBuffer('screen,mode,source,second,fps,rss_mb,image_mb\n');
    for (final r in runs.value) {
      for (var i = 0; i < r.fpsSeries.length; i++) {
        b.writeln('"${r.screen}",${r.mode.label},${r.sourceLabel},$i,${r.fpsSeries[i].toStringAsFixed(1)},'
            '${r.rssSeries[i].toStringAsFixed(1)},${r.imageSeries[i].toStringAsFixed(1)}');
      }
    }
    return b.toString();
  }

  static String _t(DateTime d) => '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
