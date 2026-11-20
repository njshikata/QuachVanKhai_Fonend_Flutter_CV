// Đường dẫn: lib/Source/perf/PerfMonitor.dart
//
// ĐO HIỆU NĂNG NGAY TRONG APP (không cần DevTools) -> hiển thị trên PerfOverlay + xuất CSV cho báo cáo.
//  - FPS & thời gian khung hình: SchedulerBinding.addTimingsCallback (FrameTiming do engine báo về:
//    thời gian build trên UI thread + raster trên GPU thread).
//  - Jank: khung hình vượt ngân sách (16.7ms ở màn 60Hz, 8.3ms ở 120Hz).
//  - RAM: ProcessInfo.currentRss (bộ nhớ thực tế tiến trình đang chiếm, Android/iOS/desktop).
//  - Ảnh: dung lượng ImageCache của Flutter (ảnh đã giải mã nằm trong RAM).
//  - Số lần build item danh sách, số request / 304 / KB tải (SyncedApi.stats).
//
// LƯU Ý BÁO CÁO: số liệu chuẩn nhất khi chạy `flutter run --profile` trên điện thoại thật
// (bản debug chạy JIT nên chậm và tốn RAM hơn nhiều so với thực tế).

import 'dart:async';
import 'dart:io' show ProcessInfo;
import 'dart:ui' show FrameTiming, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:qlpt_frontend/Source/api/SyncedApi.dart';

import 'PerfFlags.dart';

/// Bộ đếm thô, code khác tăng trực tiếp.
class PerfCounters {
  static int itemBuilds = 0;
}

class PerfSample {
  final DateTime time;
  final int frames;          // Số khung hình vẽ trong cửa sổ đo
  final double fps;
  final double buildMs;      // TB thời gian build (UI thread)
  final double rasterMs;     // TB thời gian raster (GPU thread)
  final double worstMs;      // Khung hình chậm nhất
  final int jankFrames;
  final double rssMb;        // -1 nếu nền tảng không hỗ trợ (web)
  final double imageCacheMb;
  final int liveImages;
  final int itemBuilds;      // Lũy kế
  final int netRequests;     // Lũy kế
  final int net304;
  final int netBytes;

  const PerfSample({
    required this.time,
    required this.frames,
    required this.fps,
    required this.buildMs,
    required this.rasterMs,
    required this.worstMs,
    required this.jankFrames,
    required this.rssMb,
    required this.imageCacheMb,
    required this.liveImages,
    required this.itemBuilds,
    required this.netRequests,
    required this.net304,
    required this.netBytes,
  });

  /// Gần như không có chuyển động (chỉ khung hình cập nhật bảng đo) -> không tính vào FPS trung bình.
  bool get idle => frames <= 2;

  static const String csvHeader =
      'time,frames,fps,build_ms,raster_ms,worst_ms,jank_frames,rss_mb,image_cache_mb,live_images,item_builds,net_requests,net_304,net_kb';

  String toCsv() => [
        time.toIso8601String(),
        frames,
        fps.toStringAsFixed(1),
        buildMs.toStringAsFixed(2),
        rasterMs.toStringAsFixed(2),
        worstMs.toStringAsFixed(1),
        jankFrames,
        rssMb.toStringAsFixed(1),
        imageCacheMb.toStringAsFixed(1),
        liveImages,
        itemBuilds,
        netRequests,
        net304,
        (netBytes / 1024).toStringAsFixed(1),
      ].join(',');
}

/// Kết quả 1 phiên ghi (bấm REC -> dừng).
class PerfReport {
  final String label;
  final String mode;
  final List<PerfSample> samples;

  PerfReport(this.label, this.mode, this.samples);

  Iterable<PerfSample> get _active => samples.where((s) => !s.idle);
  int get totalFrames => samples.fold(0, (a, s) => a + s.frames);
  int get jankFrames => samples.fold(0, (a, s) => a + s.jankFrames);
  double get jankPercent => totalFrames == 0 ? 0 : jankFrames * 100 / totalFrames;
  double get avgFps => _avg(_active.map((s) => s.fps));
  double get minFps => _active.isEmpty ? 0 : _active.map((s) => s.fps).reduce((a, b) => a < b ? a : b);
  double get avgFrameMs => _avg(_active.map((s) => s.buildMs + s.rasterMs));
  double get worstMs => samples.isEmpty ? 0 : samples.map((s) => s.worstMs).reduce((a, b) => a > b ? a : b);
  double get avgRss => _avg(samples.where((s) => s.rssMb >= 0).map((s) => s.rssMb));
  double get maxRss => samples.isEmpty ? 0 : samples.map((s) => s.rssMb).reduce((a, b) => a > b ? a : b);
  double get maxImageMb => samples.isEmpty ? 0 : samples.map((s) => s.imageCacheMb).reduce((a, b) => a > b ? a : b);
  int get itemBuilds => samples.isEmpty ? 0 : samples.last.itemBuilds - samples.first.itemBuilds;
  int get netRequests => samples.isEmpty ? 0 : samples.last.netRequests - samples.first.netRequests;
  int get net304 => samples.isEmpty ? 0 : samples.last.net304 - samples.first.net304;
  double get netKb => samples.isEmpty ? 0 : (samples.last.netBytes - samples.first.netBytes) / 1024;
  Duration get duration => samples.length < 2 ? Duration.zero : samples.last.time.difference(samples.first.time);

  static double _avg(Iterable<double> v) => v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;

  String summary() => '''
[$label] – $mode
Thời gian ghi: ${duration.inSeconds}s, ${samples.length} mẫu
FPS trung bình: ${avgFps.toStringAsFixed(1)} (thấp nhất ${minFps.toStringAsFixed(1)})
Thời gian khung hình TB: ${avgFrameMs.toStringAsFixed(2)} ms, chậm nhất ${worstMs.toStringAsFixed(1)} ms
Khung hình giật (jank): $jankFrames/$totalFrames (${jankPercent.toStringAsFixed(1)}%)
RAM: TB ${avgRss.toStringAsFixed(0)} MB, cao nhất ${maxRss.toStringAsFixed(0)} MB
Ảnh trong RAM cao nhất: ${maxImageMb.toStringAsFixed(1)} MB
Số lần build item: $itemBuilds
Mạng: $netRequests request, $net304 lần 304, ${netKb.toStringAsFixed(1)} KB'''
      .trim();

  String toCsv() => '# $label – $mode\n${PerfSample.csvHeader}\n${samples.map((s) => s.toCsv()).join('\n')}';
}

class PerfMonitor {
  PerfMonitor._();
  static final PerfMonitor instance = PerfMonitor._();

  /// Gắn vào MaterialApp để overlay mở được dialog.
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static const Duration interval = Duration(seconds: 1);
  static const int historyLength = 60;

  final ValueNotifier<PerfSample?> latest = ValueNotifier(null);
  final List<PerfSample> history = [];
  final List<PerfReport> reports = [];
  final ValueNotifier<bool> recording = ValueNotifier(false);
  /// Được gọi mỗi khi 1 phiên ghi kết thúc (dùng để lưu vào màn "So sánh trên app thật").
  final List<void Function(PerfReport report)> reportListeners = [];

  List<PerfSample>? _rec;
  String _recLabel = '';
  Timer? _timer;
  bool _running = false;
  double _maxRss = 0;

  // Gom FrameTiming trong cửa sổ hiện tại
  int _frames = 0;
  int _jank = 0;
  int _buildUs = 0;
  int _rasterUs = 0;
  int _worstUs = 0;
  DateTime _windowStart = DateTime.now();

  double get maxRss => _maxRss;

  double get frameBudgetMs {
    final views = PlatformDispatcher.instance.views;
    final hz = views.isEmpty ? 60.0 : views.first.display.refreshRate;
    return 1000 / (hz <= 0 ? 60 : hz);
  }

  void start() {
    if (_running) return;
    _running = true;
    _resetWindow();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _timer = Timer.periodic(interval, (_) => _tick());
  }

  void stop() {
    if (!_running) return;
    _running = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _timer?.cancel();
    _timer = null;
  }

  void startRecording(String label) {
    start();
    _recLabel = label;
    _rec = [];
    recording.value = true;
  }

  PerfReport? stopRecording() {
    final rec = _rec;
    _rec = null;
    recording.value = false;
    if (rec == null || rec.isEmpty) return null;
    final report = PerfReport(_recLabel, PerfFlags.modeLabel, rec);
    reports.insert(0, report);
    for (final l in List.of(reportListeners)) {
      l(report);
    }
    return report;
  }

  void _onTimings(List<FrameTiming> timings) {
    final budgetUs = (frameBudgetMs * 1000).round();
    for (final t in timings) {
      final b = t.buildDuration.inMicroseconds;
      final r = t.rasterDuration.inMicroseconds;
      _frames++;
      _buildUs += b;
      _rasterUs += r;
      final total = t.totalSpan.inMicroseconds;
      if (total > _worstUs) _worstUs = total;
      if (b > budgetUs || r > budgetUs) _jank++;
    }
  }

  void _tick() {
    final now = DateTime.now();
    final secs = now.difference(_windowStart).inMicroseconds / 1e6;
    double rss = -1;
    if (!kIsWeb) {
      try {
        rss = ProcessInfo.currentRss / (1024 * 1024);
      } catch (_) {}
    }
    if (rss > _maxRss) _maxRss = rss;
    final cache = PaintingBinding.instance.imageCache;
    final s = PerfSample(
      time: now,
      frames: _frames,
      fps: secs <= 0 ? 0 : _frames / secs,
      buildMs: _frames == 0 ? 0 : _buildUs / _frames / 1000,
      rasterMs: _frames == 0 ? 0 : _rasterUs / _frames / 1000,
      worstMs: _worstUs / 1000,
      jankFrames: _jank,
      rssMb: rss,
      imageCacheMb: cache.currentSizeBytes / (1024 * 1024),
      liveImages: cache.liveImageCount,
      itemBuilds: PerfCounters.itemBuilds,
      netRequests: SyncedApi.stats.requests,
      net304: SyncedApi.stats.notModified,
      netBytes: SyncedApi.stats.bytesDownloaded,
    );
    _resetWindow();
    history.add(s);
    if (history.length > historyLength) history.removeAt(0);
    _rec?.add(s);
    latest.value = s;
  }

  void _resetWindow() {
    _frames = 0;
    _jank = 0;
    _buildUs = 0;
    _rasterUs = 0;
    _worstUs = 0;
    _windowStart = DateTime.now();
  }
}
