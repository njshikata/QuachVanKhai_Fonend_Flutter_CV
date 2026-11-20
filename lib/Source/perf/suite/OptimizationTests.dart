// Đường dẫn: lib/Source/perf/suite/OptimizationTests.dart
//
// ============================================================================================
//  BỘ TEST TỐI ƯU HÓA BỘ NHỚ & GIAO DIỆN (đề tài: "Tối ưu hóa bộ nhớ và giao diện khi xử lý dữ liệu
//  trên ứng dụng di động")
// ============================================================================================
//
// Mỗi kỹ thuật tối ưu có 1 bài test riêng. Bài test chạy CÙNG một tình huống 2 lần:
//    - lượt "CHƯA tối ưu": tắt đúng kỹ thuật đang xét (các kỹ thuật khác giữ nguyên)
//    - lượt "ĐÃ tối ưu":   bật kỹ thuật đó
// rồi trả về bảng số liệu trước/sau. Bài test dùng CHÍNH code của app (PagedListView, AppNetworkImage,
// JsonIsolate, SyncedApi, MediaCachePolicy), không phải code viết riêng cho demo -> số đo phản ánh app thật.
//
// Công tắc bật/tắt trong bài test chỉ đổi TẠM THỜI trên RAM (không lưu), xong bài là trả lại như cũ.
//
//  | #  | Kỹ thuật (nội dung báo cáo)                        | Code thật nằm ở                                   |
//  |----|-----------------------------------------------------|---------------------------------------------------|
//  | T1 | ListView.builder / SliverList (render lười)         | scr/Common/PagedListView.dart, ServiceRoomScreen  |
//  | T2 | cached_network_image (cache ảnh ra đĩa)             | cache/AppNetworkImage.dart, AppCacheManager.dart  |
//  | T3 | Chính sách lưu ảnh 3 tháng / đổi chủ / phiên bản    | cache/MediaCachePolicy.dart                       |
//  | T4 | memCacheWidth / memCacheHeight (bóp độ phân giải)   | cache/AppNetworkImage.dart (_buildCached)         |
//  | T5 | ScrollController + phân trang (tải thêm khi cuộn)   | scr/Common/PagedListView.dart (_onScroll)         |
//  | T6 | compute() / Isolate cho jsonDecode                  | api/JsonIsolate.dart (dùng ở mọi file api/*)      |
//  | T7 | ValueNotifier cho từng item                         | scr/Common/PagedListView.dart (_wrap)             |
//  | T8 | ETag (304) + database phụ SQLite (bổ sung)          | api/SyncedApi.dart, local/LocalDb.dart            |
//
// DevTools: mỗi lượt đo được đánh dấu "QLPT T1 ListView.builder [CHƯA tối ưu]"... trên Timeline
// (dart:developer TimelineTask) -> mở Flutter DevTools > Performance là thấy đúng đoạn của từng bài test.

import 'dart:async';
import 'dart:developer' show TimelineTask;
import 'dart:io' show ProcessInfo;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:qlpt_frontend/Source/api/Demo/DemoAPI.dart';
import 'package:qlpt_frontend/Source/api/JsonIsolate.dart';
import 'package:qlpt_frontend/Source/api/SmartCard/SmartCardDTO.dart' show PageResult;
import 'package:qlpt_frontend/Source/api/SyncedApi.dart';
import 'package:qlpt_frontend/Source/cache/AppCacheManager.dart';
import 'package:qlpt_frontend/Source/cache/AppNetworkImage.dart';
import 'package:qlpt_frontend/Source/cache/MediaCachePolicy.dart';
import 'package:qlpt_frontend/Source/scr/Common/PagedListView.dart';

import '../PerfFlags.dart';
import '../PerfMonitor.dart';

// ============================================================================================
// KẾT QUẢ
// ============================================================================================

/// 1 dòng số liệu: giá trị CHƯA tối ưu (before) và ĐÃ tối ưu (after).
class Metric {
  final String name;
  final double? before;
  final double? after;
  final String unit;
  final bool lowerIsBetter;
  final bool key; // Chỉ số chính của bài test (dùng để kết luận Đạt/Không đạt)
  final int decimals;
  final String? beforeText; // Ghi đè cách hiển thị (vd "0/24")
  final String? afterText;

  const Metric(this.name, this.before, this.after,
      {this.unit = '', this.lowerIsBetter = true, this.key = false, this.decimals = 0, this.beforeText, this.afterText});

  String _fmt(double? v) => v == null ? '–' : '${v.toStringAsFixed(decimals)}${unit.isEmpty ? '' : ' $unit'}';
  String get beforeStr => beforeText ?? _fmt(before);
  String get afterStr => afterText ?? _fmt(after);

  /// Hệ số cải thiện (>1 = tốt hơn). null nếu không so được.
  double? get gain {
    final b = before, a = after;
    if (b == null || a == null) return null;
    if (lowerIsBetter) {
      if (a <= 0) return b > 0 ? double.infinity : null;
      return b / a;
    }
    if (b <= 0) return a > 0 ? double.infinity : null;
    return a / b;
  }

  String get gainStr {
    final g = gain;
    if (g == null) return '';
    if (g.isInfinite) return 'tuyệt đối';
    if (g >= 1.1) return '×${g.toStringAsFixed(g >= 10 ? 0 : 1)}';
    if (g <= 0.9) return 'kém hơn';
    return '≈';
  }
}

/// 1 dòng kiểm tra chức năng (dùng cho T3 – chính sách cache, không có trước/sau).
class Check {
  final String name;
  final bool ok;
  final String detail;

  const Check(this.name, this.ok, this.detail);
}

class TestResult {
  final OptimizationTest test;
  final List<Metric> metrics;
  final List<Check> checks;
  final String? error;
  final Duration took;

  const TestResult(this.test, {this.metrics = const [], this.checks = const [], this.error, this.took = Duration.zero});

  /// Đạt: chỉ số chính tốt hơn rõ (≥10%) hoặc mọi kiểm tra chức năng đều đúng.
  bool get passed {
    if (error != null) return false;
    if (checks.isNotEmpty) return checks.every((c) => c.ok);
    final keys = metrics.where((m) => m.key);
    return keys.isNotEmpty && keys.every((m) => (m.gain ?? 0) >= 1.1);
  }

  String get headline {
    if (error != null) return 'LỖI: $error';
    if (checks.isNotEmpty) return '${checks.where((c) => c.ok).length}/${checks.length} kiểm tra đúng';
    final k = metrics.where((m) => m.key).toList();
    return k.map((m) => '${m.name}: ${m.beforeStr} → ${m.afterStr} (${m.gainStr})').join(' · ');
  }

  String toMarkdown() {
    final b = StringBuffer('### ${test.id}. ${test.title} – ${passed ? 'ĐẠT ✅' : 'KHÔNG ĐẠT ❌'}\n');
    b.writeln('_${test.description}_  ');
    b.writeln('Code: `${test.codeRef}`\n');
    if (error != null) b.writeln('**Lỗi:** $error\n');
    if (metrics.isNotEmpty) {
      b.writeln('| Chỉ số | Chưa tối ưu | Đã tối ưu | Cải thiện |');
      b.writeln('|---|---|---|---|');
      for (final m in metrics) {
        b.writeln('| ${m.key ? '**${m.name}**' : m.name} | ${m.beforeStr} | ${m.afterStr} | ${m.gainStr} |');
      }
    }
    if (checks.isNotEmpty) {
      b.writeln('| Kiểm tra | Kết quả | Chi tiết |');
      b.writeln('|---|---|---|');
      for (final c in checks) {
        b.writeln('| ${c.name} | ${c.ok ? '✅' : '❌'} | ${c.detail} |');
      }
    }
    return b.toString();
  }
}

// ============================================================================================
// KHUNG CHẠY TEST (dùng chung)
// ============================================================================================

/// Môi trường chạy: hiển thị widget thử lên màn hình thật + báo tiến độ.
class TestContext {
  final NavigatorState navigator;
  final void Function(String status) report;

  TestContext(this.navigator, this.report);

  /// Mở [child] thành 1 màn hình (không hiệu ứng chuyển trang), chạy [body], rồi đóng lại.
  Future<R> host<R>(String title, Widget child, Future<R> Function() body) async {
    final route = PageRouteBuilder<void>(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => Scaffold(
        appBar: AppBar(title: Text(title, style: const TextStyle(fontSize: 15)), automaticallyImplyLeading: false),
        body: child,
      ),
    );
    unawaited(navigator.push(route));
    await WidgetsBinding.instance.endOfFrame;
    try {
      return await body();
    } finally {
      if (route.isActive) navigator.removeRoute(route);
      await WidgetsBinding.instance.endOfFrame;
    }
  }
}

/// Đổi tạm các công tắc tối ưu (CHỈ trên RAM, không lưu), chạy [fn], rồi trả lại như cũ.
Future<T> withFlags<T>(Map<PerfFlag, bool> values, Future<T> Function() fn) async {
  final saved = {for (final f in PerfFlags.optimizations) f: f.value};
  values.forEach((f, v) => f.notifier.value = v);
  try {
    return await fn();
  } finally {
    saved.forEach((f, v) => f.notifier.value = v);
  }
}

/// RAM thực tế tiến trình đang chiếm (MB). Web không đo được -> null.
double? currentRssMb() {
  if (kIsWeb) return null;
  try {
    return ProcessInfo.currentRss / (1024 * 1024);
  } catch (_) {
    return null;
  }
}

/// Xóa mọi cache để các lượt đo bắt đầu như nhau.
Future<void> coldCaches({bool disk = true}) async {
  PaintingBinding.instance.imageCache
    ..clear()
    ..clearLiveImages();
  if (disk) await AppCacheManager.instance.emptyCache();
  await SyncedApi.clear();
  SyncedApi.stats.reset();
}

/// Ghi lại thời gian từng khung hình (FrameTiming) trong lúc đo.
class FrameRecorder {
  final List<FrameTiming> frames = [];
  final Stopwatch _sw = Stopwatch();

  void _cb(List<FrameTiming> t) => frames.addAll(t);

  void start() {
    frames.clear();
    SchedulerBinding.instance.addTimingsCallback(_cb);
    _sw
      ..reset()
      ..start();
  }

  Future<void> stop() async {
    _sw.stop();
    // Engine gửi FrameTiming theo lô (~1 giây/lần) -> đợi nhận nốt
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    SchedulerBinding.instance.removeTimingsCallback(_cb);
  }

  double get fps => _sw.elapsedMilliseconds == 0 ? 0 : frames.length * 1000 / _sw.elapsedMilliseconds;

  double _ms(Duration d) => d.inMicroseconds / 1000;
  double get avgBuildMs => frames.isEmpty ? 0 : frames.map((f) => _ms(f.buildDuration)).reduce((a, b) => a + b) / frames.length;
  double get totalBuildMs => frames.fold(0, (a, f) => a + _ms(f.buildDuration));
  double get worstMs => frames.isEmpty
      ? 0
      : frames.map((f) => _ms(f.buildDuration) > _ms(f.rasterDuration) ? _ms(f.buildDuration) : _ms(f.rasterDuration)).reduce((a, b) => a > b ? a : b);
  double get jankPercent => frames.isEmpty
      ? 0
      : frames.where((f) => _ms(f.buildDuration) > 16.7 || _ms(f.rasterDuration) > 16.7).length * 100 / frames.length;
}

/// Tự cuộn đều ~2400 px/giây trong [duration]; hết danh sách thì nhảy lên đầu.
Future<void> autoScroll(ScrollController c, Duration duration, {bool Function()? hasMore}) async {
  final sw = Stopwatch()..start();
  while (sw.elapsed < duration) {
    if (!c.hasClients) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      continue;
    }
    final max = c.position.maxScrollExtent;
    final target = c.offset + 1200;
    if (target >= max && !(hasMore?.call() ?? false)) {
      if (max > c.offset) await c.animateTo(max, duration: const Duration(milliseconds: 250), curve: Curves.linear);
      c.jumpTo(0);
      await WidgetsBinding.instance.endOfFrame;
      continue;
    }
    await c.animateTo(target < max ? target : max, duration: const Duration(milliseconds: 500), curve: Curves.linear);
  }
}

/// Đợi tới khi [cond] đúng (kiểm tra mỗi frame), quá [timeout] thì báo lỗi.
Future<void> waitUntil(bool Function() cond, {Duration timeout = const Duration(seconds: 60), String what = ''}) async {
  final sw = Stopwatch()..start();
  while (!cond()) {
    if (sw.elapsed > timeout) throw TimeoutException('Quá ${timeout.inSeconds}s chờ $what');
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }
}

/// Đánh dấu 1 lượt đo trên Timeline của DevTools.
Future<T> traced<T>(String label, Future<T> Function() fn) async {
  final task = TimelineTask()..start('QLPT $label');
  try {
    return await fn();
  } finally {
    task.finish();
  }
}

// ============================================================================================
// ĐỊNH NGHĨA BÀI TEST
// ============================================================================================

abstract class OptimizationTest {
  String get id;
  String get title;
  String get description; // Kỹ thuật làm gì + đo cái gì (để trình bày)
  String get codeRef;
  bool get needsServer => true;

  Future<TestResult> run(TestContext ctx);

  /// Chạy [mode] 2 lượt: false = CHƯA tối ưu, true = ĐÃ tối ưu.
  Future<(T, T)> both<T>(TestContext ctx, Future<T> Function(bool optimized) mode) async {
    ctx.report('$id: lượt CHƯA tối ưu...');
    final before = await traced('$id $title [CHƯA tối ưu]', () => mode(false));
    await Future<void>.delayed(const Duration(milliseconds: 800)); // Cho CPU/mạng nghỉ giữa 2 lượt
    ctx.report('$id: lượt ĐÃ tối ưu...');
    final after = await traced('$id $title [ĐÃ tối ưu]', () => mode(true));
    return (before, after);
  }
}

/// Danh sách đầy đủ, theo thứ tự trình bày.
final List<OptimizationTest> allOptimizationTests = [
  ListBuilderTest(),
  DiskCacheTest(),
  CachePolicyTest(),
  MemCacheWidthTest(),
  PagingTest(),
  ComputeJsonTest(),
  ValueNotifierTest(),
  EtagTest(),
];

// Dữ liệu cục bộ dùng cho T1/T7 (không qua mạng -> chỉ đo phần giao diện)
class _Row {
  final int id;
  final bool selected;

  const _Row(this.id, {this.selected = false});

  _Row toggle() => _Row(id, selected: !selected);
}

PageFetcher<_Row> _localFetch(int total) => (page, size) async {
      if (size <= 0) size = total;
      final from = page * size;
      final to = (from + size) > total ? total : from + size;
      return PageResult(items: [for (var i = from; i < to; i++) _Row(i)], page: page, hasNext: to < total);
    };

Widget _rowTile(BuildContext context, ValueNotifier<_Row> item, int index) => ValueListenableBuilder<_Row>(
      valueListenable: item,
      builder: (context, r, _) => ListTile(
        dense: true,
        leading: CircleAvatar(radius: 16, child: Text('${r.id % 100}', style: const TextStyle(fontSize: 11))),
        title: Text('Phòng ${101 + r.id} · Khách thuê #${r.id}'),
        subtitle: Text(r.selected ? 'ĐÃ CHỌN' : 'Đang thuê · hợp đồng 12 tháng'),
        trailing: Icon(r.selected ? Icons.check_box : Icons.check_box_outline_blank,
            color: r.selected ? Colors.green : Colors.grey),
      ),
    );

// --------------------------------------------------------------------------------------------
// T1. ListView.builder
// --------------------------------------------------------------------------------------------
class ListBuilderTest extends OptimizationTest {
  static const int total = 3000;

  @override
  String get id => 'T1';
  @override
  String get title => 'ListView.builder / SliverList';
  @override
  String get description =>
      'Danh sách $total dòng. CHƯA tối ưu: Column trong SingleChildScrollView -> build cả $total dòng ngay khi mở. '
      'ĐÃ tối ưu: ListView.builder -> chỉ build các dòng đang nằm trong khung nhìn (+ vùng đệm nhỏ).';
  @override
  String get codeRef => 'lib/Source/scr/Common/PagedListView.dart (nhánh _useBuilder)';
  @override
  bool get needsServer => false;

  @override
  Future<TestResult> run(TestContext ctx) async {
    final r = await both(ctx, (opt) => withFlags({
          PerfFlags.listBuilder: opt,
          PerfFlags.paging: false, // Có đủ $total dòng trong RAM ở cả 2 lượt -> chỉ khác cách render
          PerfFlags.itemNotifier: true,
        }, () async {
          final key = GlobalKey<PagedListViewState<_Row>>();
          final rss0 = currentRssMb();
          PerfCounters.itemBuilds = 0;
          final sw = Stopwatch()..start();
          return ctx.host(
            'T1 ${opt ? 'ListView.builder' : 'Column (build hết)'}',
            PagedListView<_Row>(key: key, fetch: _localFetch(total), unpagedPageSize: total, itemExtent: 64, itemBuilder: _rowTile),
            () async {
              await waitUntil(() => PerfCounters.itemBuilds > 0, what: 'danh sách hiện');
              await WidgetsBinding.instance.endOfFrame;
              final openMs = sw.elapsedMilliseconds.toDouble();
              final built = PerfCounters.itemBuilds.toDouble();
              final rss1 = currentRssMb();
              final rec = FrameRecorder()..start();
              await autoScroll(key.currentState!.scrollController, const Duration(seconds: 4));
              await rec.stop();
              return [openMs, built, rss0 == null || rss1 == null ? null : rss1 - rss0, rec.fps, rec.jankPercent];
            },
          );
        }));
    final b = r.$1, a = r.$2;
    return TestResult(this, metrics: [
      Metric('Thời gian mở danh sách', b[0], a[0], unit: 'ms', key: true),
      Metric('Số dòng phải build khi mở', b[1], a[1], key: true),
      Metric('RAM tăng thêm khi mở', b[2], a[2], unit: 'MB', decimals: 1),
      Metric('FPS khi cuộn', b[3], a[3], lowerIsBetter: false),
      Metric('Khung hình giật', b[4], a[4], unit: '%'),
    ]);
  }
}

// --------------------------------------------------------------------------------------------
// Lưới ảnh dùng cho T2/T4: báo khi tất cả ảnh đã hiện xong
// --------------------------------------------------------------------------------------------
class _ImageGrid extends StatelessWidget {
  final List<String> urls;
  final double tile;
  final void Function(bool ok) onSettled;

  const _ImageGrid({required this.urls, required this.tile, required this.onSettled});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(4),
        child: Wrap(spacing: 4, runSpacing: 4, children: [
          for (final u in urls)
            AppNetworkImage(
              url: u,
              width: tile,
              height: tile,
              authenticated: false,
              fallbackIcon: Icons.image,
              placeholder: (_) => const ColoredBox(color: Color(0xFFE0E0E0)),
              onSettled: onSettled,
            ),
        ]),
      );
}

/// Mở lưới ảnh, trả về (thời gian tới khi mọi ảnh hiện xong, số ảnh lỗi).
Future<(double, int)> _showImages(TestContext ctx, String title, List<String> urls, double tile) async {
  var settled = 0, errors = 0;
  final sw = Stopwatch()..start();
  return ctx.host(title, _ImageGrid(urls: urls, tile: tile, onSettled: (ok) {
    settled++;
    if (!ok) errors++;
  }), () async {
    await waitUntil(() => settled >= urls.length, what: 'tải ảnh');
    return (sw.elapsedMilliseconds.toDouble(), errors);
  });
}

int _imageSeed = DateTime.now().millisecondsSinceEpoch % 100000; // URL mới mỗi lần chạy -> không dính cache cũ

// --------------------------------------------------------------------------------------------
// T2. cached_network_image
// --------------------------------------------------------------------------------------------
class DiskCacheTest extends OptimizationTest {
  static const int count = 24;

  @override
  String get id => 'T2';
  @override
  String get title => 'cached_network_image (cache ảnh ra đĩa)';
  @override
  String get description =>
      'Mở $count ảnh từ API, xóa cache RAM (giống tắt app mở lại) rồi mở lại. CHƯA tối ưu: Image.network -> lần 2 '
      'tải lại toàn bộ qua mạng. ĐÃ tối ưu: CachedNetworkImage -> lần 2 đọc file trong máy, không tốn mạng.';
  @override
  String get codeRef => 'lib/Source/cache/AppNetworkImage.dart + AppCacheManager.dart';

  @override
  Future<TestResult> run(TestContext ctx) async {
    final r = await both(ctx, (opt) => withFlags({PerfFlags.imageDiskCache: opt, PerfFlags.imageResize: true}, () async {
          await coldCaches();
          final base = 200000 + (_imageSeed += 100);
          final urls = [for (var i = 0; i < count; i++) '/api/landlord/demo/img/${base + i}?w=300'];
          final first = await _showImages(ctx, 'T2 lần 1 – tải qua mạng', urls, 72);
          // Giống tắt app mở lại: xóa ảnh trong RAM, giữ file trên đĩa
          PaintingBinding.instance.imageCache
            ..clear()
            ..clearLiveImages();
          var onDisk = 0;
          for (final u in urls) {
            if (await AppCacheManager.instance.getFileFromCache(AppNetworkImage.resolve(u)) != null) onDisk++;
          }
          final second = await _showImages(ctx, 'T2 lần 2 – mở lại', urls, 72);
          return [first.$1, second.$1, onDisk.toDouble(), (first.$2 + second.$2).toDouble()];
        }));
    final b = r.$1, a = r.$2;
    return TestResult(this, metrics: [
      Metric('Lần 1: tải $count ảnh qua mạng', b[0], a[0], unit: 'ms'),
      // Chỉ số chính = số request mạng khi mở lại. Thời gian chỉ để tham khảo: mạng LAN/wifi nội bộ tải 24 ảnh
      // nhỏ rất nhanh nên chênh ít; trên 4G/mạng yếu hoặc mất mạng thì bản không cache chậm hẳn / không hiện ảnh.
      Metric('Lần 2: mở lại (sau khi xóa RAM)', b[1], a[1], unit: 'ms'),
      Metric('Request mạng khi mở lại', count - b[2], count - a[2], key: true),
      Metric('Ảnh có sẵn trong máy ở lần 2', b[2], a[2], lowerIsBetter: false,
          beforeText: '${b[2].toInt()}/$count', afterText: '${a[2].toInt()}/$count'),
      Metric('Ảnh lỗi', b[3], a[3]),
    ]);
  }
}

// --------------------------------------------------------------------------------------------
// T3. Chính sách lưu ảnh (3 tháng, đổi chủ phòng, phiên bản)
// --------------------------------------------------------------------------------------------
class CachePolicyTest extends OptimizationTest {
  @override
  String get id => 'T3';
  @override
  String get title => 'Chính sách lưu ảnh: 3 tháng / đổi chủ / phiên bản';
  @override
  String get description =>
      'Kiểm tra chức năng (tua nhanh đồng hồ, không phải chờ thật): ảnh quá 90 ngày bị xóa khỏi máy; '
      'phòng đổi chủ thì ảnh của chủ cũ (CCCD, ảnh thẻ...) bị xóa sau 30 ngày, ảnh chủ mới giữ nguyên; '
      'ảnh có phiên bản mới thì bản cũ bị xóa ngay. Server giữ ảnh 2 năm, quá hạn trả 204 rỗng -> app hiện ảnh mặc định.';
  @override
  String get codeRef => 'lib/Source/cache/MediaCachePolicy.dart';
  @override
  bool get needsServer => false;

  @override
  Future<TestResult> run(TestContext ctx) async {
    ctx.report('T3: kiểm tra chính sách lưu ảnh...');
    final checks = <Check>[];
    final realNow = DateTime.now();
    final bytes = Uint8List.fromList(List.filled(256, 7)); // File ảnh giả nhỏ, chỉ để có file trong cache
    final cm = AppCacheManager.instance;
    const room = 990001; // Phòng giả, không đụng dữ liệu thật
    final tag = 'test-${realNow.millisecondsSinceEpoch}';

    Future<bool> onDisk(String k) async => await cm.getFileFromCache(k) != null;
    Future<void> put(String k, MediaCacheTag t) async {
      await cm.putFile('https://test.local/$k', bytes, key: k, fileExtension: 'jpg');
      await MediaCachePolicy.track(k, t);
    }

    try {
      // 1. Quá 90 ngày
      final old = '$tag-90d';
      await put(old, const MediaCacheTag());
      MediaCachePolicy.clock = () => realNow.add(const Duration(days: 89));
      await MediaCachePolicy.runCleanupNow();
      final keep89 = await onDisk(old);
      MediaCachePolicy.clock = () => realNow.add(const Duration(days: 91));
      await MediaCachePolicy.runCleanupNow();
      final gone91 = !await onDisk(old) && !await MediaCachePolicy.isTracked(old);
      checks.add(Check('Ảnh 89 ngày tuổi vẫn giữ', keep89, keep89 ? 'còn trong máy' : 'bị xóa sớm'));
      checks.add(Check('Ảnh 91 ngày tuổi bị xóa', gone91, gone91 ? 'đã xóa file + chỉ mục' : 'vẫn còn'));

      // 2. Đổi chủ phòng
      MediaCachePolicy.clock = () => realNow;
      final oldOwnerImg = '$tag-cccd-owner1';
      final newOwnerImg = '$tag-cccd-owner2';
      await MediaCachePolicy.onRoomOwner(roomId: room, currentOwnerId: 1);
      await put(oldOwnerImg, const MediaCacheTag(group: 'cccd:1', ownerId: 1, roomId: room));
      await MediaCachePolicy.onRoomOwner(roomId: room, currentOwnerId: 2, previousOwnerId: 1, ownerChangedAt: realNow);
      await put(newOwnerImg, const MediaCacheTag(group: 'cccd:2', ownerId: 2, roomId: room));
      MediaCachePolicy.clock = () => realNow.add(const Duration(days: 29));
      await MediaCachePolicy.runCleanupNow();
      final keep29 = await onDisk(oldOwnerImg);
      MediaCachePolicy.clock = () => realNow.add(const Duration(days: 31));
      await MediaCachePolicy.runCleanupNow();
      final gone31 = !await onDisk(oldOwnerImg);
      final newKept = await onDisk(newOwnerImg);
      checks.add(Check('Đổi chủ 29 ngày: ảnh chủ cũ còn giữ', keep29, keep29 ? 'còn' : 'bị xóa sớm'));
      checks.add(Check('Đổi chủ 31 ngày: ảnh chủ cũ bị xóa', gone31, gone31 ? 'đã xóa' : 'vẫn còn'));
      checks.add(Check('Ảnh của chủ mới không bị xóa', newKept, newKept ? 'còn' : 'bị xóa nhầm'));

      // 3. Phiên bản: v2 về thì v1 bị xóa ngay
      MediaCachePolicy.clock = () => realNow;
      final v1 = '$tag-photo:v1', v2 = '$tag-photo:v2';
      await put(v1, MediaCacheTag(group: '$tag-photo'));
      await put(v2, MediaCacheTag(group: '$tag-photo'));
      final v1Gone = !await onDisk(v1);
      final v2Kept = await onDisk(v2);
      checks.add(Check('Có phiên bản mới: bản cũ bị xóa ngay', v1Gone && v2Kept,
          'v1 ${v1Gone ? 'đã xóa' : 'còn'}, v2 ${v2Kept ? 'còn' : 'mất'}'));

      // Dọn file test
      for (final k in [old, oldOwnerImg, newOwnerImg, v1, v2]) {
        await cm.removeFile(k);
      }
      return TestResult(this, checks: checks);
    } finally {
      MediaCachePolicy.clock = DateTime.now;
    }
  }
}

// --------------------------------------------------------------------------------------------
// T4. memCacheWidth / memCacheHeight
// --------------------------------------------------------------------------------------------
class MemCacheWidthTest extends OptimizationTest {
  static const int count = 12;

  @override
  String get id => 'T4';
  @override
  String get title => 'memCacheWidth / memCacheHeight (giảm độ phân giải trước khi lên RAM)';
  @override
  String get description =>
      '$count ảnh GỐC 1600x1200 hiển thị trong ô 100dp. CHƯA tối ưu: giải mã nguyên ảnh (~7,3 MB RAM/ảnh). '
      'ĐÃ tối ưu: memCacheWidth = 100dp x mật độ điểm ảnh -> chỉ giải mã đúng cỡ ô. File ảnh đã có sẵn trên đĩa '
      'ở cả 2 lượt nên chỉ khác phần giải mã.';
  @override
  String get codeRef => 'lib/Source/cache/AppNetworkImage.dart (_buildCached: memCacheWidth/memCacheHeight)';

  @override
  Future<TestResult> run(TestContext ctx) async {
    final base = 300000 + (_imageSeed += 100);
    final urls = [for (var i = 0; i < count; i++) '/api/landlord/demo/img/${base + i}']; // Ảnh gốc 1600px
    ctx.report('T4: tải trước $count ảnh gốc về đĩa...');
    await coldCaches();
    for (final u in urls) {
      await AppCacheManager.instance.downloadFile(AppNetworkImage.resolve(u));
    }
    final r = await both(ctx, (opt) => withFlags({PerfFlags.imageResize: opt, PerfFlags.imageDiskCache: true}, () async {
          final cache = PaintingBinding.instance.imageCache
            ..clear()
            ..clearLiveImages();
          await Future<void>.delayed(const Duration(milliseconds: 300));
          final rss0 = currentRssMb();
          final shown = await _showImages(ctx, 'T4 ${opt ? 'memCacheWidth' : 'ảnh gốc'}', urls, 100);
          final imgMb = cache.currentSizeBytes / (1024 * 1024);
          final rss1 = currentRssMb();
          return [imgMb, rss0 == null || rss1 == null ? null : rss1 - rss0, shown.$1];
        }));
    final b = r.$1, a = r.$2;
    return TestResult(this, metrics: [
      Metric('RAM ảnh đã giải mã ($count ảnh)', b[0], a[0], unit: 'MB', decimals: 1, key: true),
      Metric('RAM app tăng thêm', b[1], a[1], unit: 'MB', decimals: 1),
      Metric('Thời gian hiện đủ $count ảnh', b[2], a[2], unit: 'ms'),
    ]);
  }
}

// --------------------------------------------------------------------------------------------
// T5. ScrollController + phân trang
// --------------------------------------------------------------------------------------------
class PagingTest extends OptimizationTest {
  static const int total = 5000;

  @override
  String get id => 'T5';
  @override
  String get title => 'ScrollController + phân trang (tải thêm khi cuộn gần cuối)';
  @override
  String get description =>
      'Danh sách $total phần tử từ API. CHƯA tối ưu: tải toàn bộ $total phần tử rồi mới hiện. ĐÃ tối ưu: tải trang '
      '20 phần tử; ScrollController thấy còn cách cuối ~400px thì gọi API trang kế tiếp.';
  @override
  String get codeRef => 'lib/Source/scr/Common/PagedListView.dart (_onScroll, _loadMore)';

  @override
  Future<TestResult> run(TestContext ctx) async {
    final r = await both(ctx, (opt) => withFlags({
          PerfFlags.paging: opt,
          PerfFlags.listBuilder: true,
          PerfFlags.isolateJson: true,
          PerfFlags.etagLocalDb: false, // Mỗi request đều đi mạng -> đếm đúng số byte
        }, () async {
          await coldCaches(disk: false);
          final key = GlobalKey<PagedListViewState<DemoItem>>();
          PerfCounters.itemBuilds = 0;
          final sw = Stopwatch()..start();
          return ctx.host(
            'T5 ${opt ? 'phân trang' : 'tải hết'}',
            PagedListView<DemoItem>(
              key: key,
              fetch: (p, s) => DemoAPI.feed(p, s, total),
              pageSize: 20,
              unpagedPageSize: 0, // 0 = server trả tất cả trong 1 lần
              itemExtent: 56,
              itemBuilder: (c, item, i) => ListTile(dense: true, title: Text('#${item.value.id} ${item.value.title}'), subtitle: Text(item.value.room)),
            ),
            () async {
              await waitUntil(() => PerfCounters.itemBuilds > 0, what: 'dữ liệu đầu tiên');
              final firstMs = sw.elapsedMilliseconds.toDouble();
              final kb = SyncedApi.stats.bytesDownloaded / 1024;
              final inRam = key.currentState!.items.length.toDouble();
              final req0 = SyncedApi.stats.requests;
              await autoScroll(key.currentState!.scrollController, const Duration(seconds: 3),
                  hasMore: () => key.currentState?.hasMore ?? false);
              final moreReq = (SyncedApi.stats.requests - req0).toDouble();
              return [firstMs, kb, inRam, moreReq];
            },
          );
        }));
    final b = r.$1, a = r.$2;
    return TestResult(this, metrics: [
      Metric('Thời gian hiện dữ liệu đầu tiên', b[0], a[0], unit: 'ms', key: true),
      Metric('Dữ liệu tải lúc mở', b[1], a[1], unit: 'KB', key: true),
      Metric('Số phần tử giữ trong RAM lúc mở', b[2], a[2]),
      Metric('Số lần gọi API khi cuộn 3s (tải thêm)', b[3], a[3], lowerIsBetter: false,
          beforeText: '${b[3].toInt()} (đã có hết)', afterText: '${a[3].toInt()} trang'),
    ]);
  }
}

// --------------------------------------------------------------------------------------------
// T6. compute() / Isolate cho jsonDecode
// --------------------------------------------------------------------------------------------
class ComputeJsonTest extends OptimizationTest {
  static const int total = 5000;

  @override
  String get id => 'T6';
  @override
  String get title => 'compute() / Isolate cho jsonDecode';
  @override
  String get description =>
      'Parse JSON $total phần tử (~2MB) bằng đúng hàm JsonIsolate.decode() mà tầng api/ dùng. CHƯA tối ưu: '
      'jsonDecode trên UI thread -> giao diện đứng hình trong lúc parse. ĐÃ tối ưu: compute() đẩy sang Isolate nền. '
      '"UI đứng" = khoảng lặng dài nhất của 1 bộ đếm 8ms chạy song song trên UI thread.';
  @override
  String get codeRef => 'lib/Source/api/JsonIsolate.dart';

  static Future<(int, int)> _measureBlocking(Future<dynamic> Function() fn) async {
    var maxGap = 0;
    var last = DateTime.now();
    final timer = Timer.periodic(const Duration(milliseconds: 8), (_) {
      final now = DateTime.now();
      final gap = now.difference(last).inMilliseconds;
      if (gap > maxGap) maxGap = gap;
      last = now;
    });
    await Future<void>.delayed(const Duration(milliseconds: 80));
    maxGap = 0;
    final sw = Stopwatch()..start();
    await fn();
    sw.stop();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    timer.cancel();
    return (sw.elapsedMilliseconds, maxGap);
  }

  @override
  Future<TestResult> run(TestContext ctx) async {
    ctx.report('T6: tải JSON $total phần tử...');
    final bytes = await DemoAPI.rawFeed(total);
    final r = await both(ctx, (opt) => withFlags({PerfFlags.isolateJson: opt}, () async {
          final m = await _measureBlocking(() => JsonIsolate.decode(bytes));
          return [m.$1.toDouble(), m.$2.toDouble()];
        }));
    final b = r.$1, a = r.$2;
    return TestResult(this, metrics: [
      Metric('Kích thước JSON', bytes.length / 1024, bytes.length / 1024, unit: 'KB'),
      Metric('Thời gian parse', b[0], a[0], unit: 'ms'),
      Metric('UI bị đứng lâu nhất', b[1], a[1], unit: 'ms', key: true),
      Metric('Khung hình bị mất (≈ UI đứng / 16,7ms)', (b[1] / 16.7).floorToDouble(), (a[1] / 16.7).floorToDouble()),
    ]);
  }
}

// --------------------------------------------------------------------------------------------
// T7. ValueNotifier cho từng item
// --------------------------------------------------------------------------------------------
class ValueNotifierTest extends OptimizationTest {
  static const int taps = 30;

  @override
  String get id => 'T7';
  @override
  String get title => 'ValueNotifier cho từng item';
  @override
  String get description =>
      'Bấm chọn / bỏ chọn $taps lần trên các dòng của danh sách. CHƯA tối ưu: setState() cả danh sách -> mọi dòng '
      'đang hiện đều build lại. ĐÃ tối ưu: mỗi dòng bọc ValueNotifier + ValueListenableBuilder -> chỉ đúng dòng đó build lại.';
  @override
  String get codeRef => 'lib/Source/scr/Common/PagedListView.dart (_wrap, _rebuildAll)';
  @override
  bool get needsServer => false;

  @override
  Future<TestResult> run(TestContext ctx) async {
    final r = await both(ctx, (opt) => withFlags({PerfFlags.itemNotifier: opt, PerfFlags.listBuilder: true, PerfFlags.paging: false}, () async {
          final key = GlobalKey<PagedListViewState<_Row>>();
          return ctx.host(
            'T7 ${opt ? 'ValueNotifier' : 'setState cả list'}',
            PagedListView<_Row>(key: key, fetch: _localFetch(500), unpagedPageSize: 500, itemExtent: 64, itemBuilder: _rowTile),
            () async {
              await waitUntil(() => (key.currentState?.items.length ?? 0) > 0, what: 'danh sách');
              await WidgetsBinding.instance.endOfFrame;
              final items = key.currentState!.items;
              PerfCounters.itemBuilds = 0;
              final rec = FrameRecorder()..start();
              for (var i = 0; i < taps; i++) {
                final it = items[i % 8];
                it.value = (it.value).toggle();
                await WidgetsBinding.instance.endOfFrame;
              }
              await rec.stop();
              return [PerfCounters.itemBuilds.toDouble(), rec.totalBuildMs];
            },
          );
        }));
    final b = r.$1, a = r.$2;
    return TestResult(this, metrics: [
      Metric('Số dòng phải build lại ($taps lần bấm)', b[0], a[0], key: true),
      Metric('Tổng thời gian build (UI thread)', b[1], a[1], unit: 'ms', decimals: 1),
    ]);
  }
}

// --------------------------------------------------------------------------------------------
// T8. ETag + SQLite (bổ sung)
// --------------------------------------------------------------------------------------------
class EtagTest extends OptimizationTest {
  static const int total = 2000;

  @override
  String get id => 'T8';
  @override
  String get title => 'ETag (304) + database phụ SQLite (bổ sung)';
  @override
  String get description =>
      'Tải 1 danh sách $total phần tử 2 lần liên tiếp (dữ liệu không đổi). CHƯA tối ưu: lần 2 tải lại & parse lại '
      'toàn bộ. ĐÃ tối ưu: gửi If-None-Match, server trả 304 (không có body) -> dùng bản đã lưu trong máy.';
  @override
  String get codeRef => 'lib/Source/api/SyncedApi.dart + lib/Source/local/LocalDb.dart';

  @override
  Future<TestResult> run(TestContext ctx) async {
    final path = DemoAPI.feedPath(page: 0, size: 0, total: total);
    final r = await both(ctx, (opt) => withFlags({PerfFlags.etagLocalDb: opt}, () async {
          await coldCaches(disk: false);
          await SyncedApi.getJson(path); // Lần 1
          final kb0 = SyncedApi.stats.bytesDownloaded;
          final sw = Stopwatch()..start();
          await SyncedApi.getJson(path); // Lần 2 – thứ được đo
          return [(SyncedApi.stats.bytesDownloaded - kb0) / 1024, sw.elapsedMilliseconds.toDouble()];
        }));
    final b = r.$1, a = r.$2;
    return TestResult(this, metrics: [
      Metric('Dữ liệu tải ở lần 2', b[0], a[0], unit: 'KB', decimals: 1, key: true),
      Metric('Thời gian lần 2', b[1], a[1], unit: 'ms'),
    ]);
  }
}
