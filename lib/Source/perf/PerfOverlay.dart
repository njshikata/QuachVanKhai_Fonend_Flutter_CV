// Đường dẫn: lib/Source/perf/PerfOverlay.dart
//
// BẢNG FPS / RAM NỔI TRÊN MỌI MÀN HÌNH (bật/tắt trong "Hiệu năng & Demo").
//  - Kéo để di chuyển, chạm để thu gọn / mở rộng.
//  - Nút ● REC: ghi số liệu từng giây -> dừng sẽ ra bảng tổng kết + copy CSV dán vào Excel/báo cáo.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'PerfFlags.dart';
import 'PerfMonitor.dart';

/// Bọc toàn app (MaterialApp.builder).
class PerfOverlayHost extends StatelessWidget {
  final Widget child;

  const PerfOverlayHost({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: PerfFlags.showOverlay.notifier,
      builder: (context, show, _) {
        if (show) {
          PerfMonitor.instance.start();
        } else if (!PerfMonitor.instance.recording.value) {
          PerfMonitor.instance.stop();
        }
        return Stack(children: [child, if (show) const _DraggablePanel()]);
      },
    );
  }
}

class _DraggablePanel extends StatefulWidget {
  const _DraggablePanel();

  @override
  State<_DraggablePanel> createState() => _DraggablePanelState();
}

class _DraggablePanelState extends State<_DraggablePanel> {
  Offset _pos = const Offset(8, 90);
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Positioned(
      left: _pos.dx.clamp(0, size.width - 60),
      top: _pos.dy.clamp(0, size.height - 40),
      child: GestureDetector(
        onPanUpdate: (d) => setState(() => _pos += d.delta),
        onTap: () => setState(() => _expanded = !_expanded),
        // RepaintBoundary: bảng tự vẽ lại mỗi giây nhưng không kéo cả màn hình vẽ lại theo
        child: RepaintBoundary(
          child: Material(
            color: Colors.black.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(10),
            child: DefaultTextStyle(
              style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace', height: 1.35),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: ValueListenableBuilder<PerfSample?>(
                  valueListenable: PerfMonitor.instance.latest,
                  builder: (context, s, _) => _expanded ? _full(s) : _compact(s),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _fpsColor(PerfSample? s) {
    if (s == null || s.idle) return Colors.white70;
    if (s.fps >= 50) return Colors.greenAccent;
    if (s.fps >= 30) return Colors.amberAccent;
    return Colors.redAccent;
  }

  String _fps(PerfSample? s) => s == null ? '--' : (s.idle ? 'nghỉ' : s.fps.toStringAsFixed(0));

  String _ram(PerfSample? s) => s == null || s.rssMb < 0 ? 'n/a' : '${s.rssMb.toStringAsFixed(0)}MB';

  Widget _compact(PerfSample? s) => Text('FPS ${_fps(s)} · ${_ram(s)}',
      style: TextStyle(color: _fpsColor(s), fontWeight: FontWeight.bold));

  Widget _full(PerfSample? s) {
    final m = PerfMonitor.instance;
    final optimized = PerfFlags.allOptimized;
    return SizedBox(
      width: 210,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Expanded(
              child: Text(PerfFlags.modeLabel,
                  style: TextStyle(
                      color: optimized ? Colors.greenAccent : Colors.orangeAccent, fontWeight: FontWeight.bold)),
            ),
            _recButton(),
          ]),
          Text('FPS   ${_fps(s).padRight(5)} jank ${s?.jankFrames ?? 0}/${s?.frames ?? 0}',
              style: TextStyle(color: _fpsColor(s), fontWeight: FontWeight.bold)),
          Text('Build ${(s?.buildMs ?? 0).toStringAsFixed(1)}ms  Raster ${(s?.rasterMs ?? 0).toStringAsFixed(1)}ms'),
          Text('Max   ${(s?.worstMs ?? 0).toStringAsFixed(1)}ms (ngân sách ${m.frameBudgetMs.toStringAsFixed(1)})'),
          Text('RAM   ${_ram(s)} (đỉnh ${m.maxRss.toStringAsFixed(0)}MB)'),
          Text('Ảnh   ${(s?.imageCacheMb ?? 0).toStringAsFixed(1)}MB · ${s?.liveImages ?? 0} ảnh'),
          Text('Item build: ${s?.itemBuilds ?? 0}'),
          Text('Mạng  ${s?.netRequests ?? 0} req · 304: ${s?.net304 ?? 0} · ${((s?.netBytes ?? 0) / 1024).toStringAsFixed(0)}KB'),
          const SizedBox(height: 4),
          SizedBox(
            height: 28,
            width: 210,
            child: CustomPaint(painter: _SparkPainter(m.history)),
          ),
          const Text('— FPS   — RAM', style: TextStyle(fontSize: 9, color: Colors.white54)),
        ],
      ),
    );
  }

  Widget _recButton() {
    return ValueListenableBuilder<bool>(
      valueListenable: PerfMonitor.instance.recording,
      builder: (context, rec, _) => GestureDetector(
        onTap: () async {
          if (!rec) {
            PerfMonitor.instance.startRecording('Ghi ${DateTime.now().toString().substring(11, 19)}');
          } else {
            final r = PerfMonitor.instance.stopRecording();
            final ctx = PerfMonitor.navigatorKey.currentContext;
            if (r != null && ctx != null) showPerfReportDialog(ctx, r);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: rec ? Colors.red : Colors.white24,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(rec ? '■ STOP' : '● REC', style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<PerfSample> data;

  _SparkPainter(List<PerfSample> d) : data = List.of(d);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    _line(canvas, size, data.map((s) => s.idle ? 60.0 : s.fps.clamp(0, 120).toDouble()).toList(), 120,
        Colors.greenAccent);
    final rss = data.map((s) => s.rssMb < 0 ? 0.0 : s.rssMb).toList();
    final maxRss = rss.reduce((a, b) => a > b ? a : b);
    _line(canvas, size, rss, maxRss <= 0 ? 1 : maxRss * 1.1, Colors.lightBlueAccent);
  }

  void _line(Canvas canvas, Size size, List<double> v, double maxV, Color color) {
    final path = Path();
    final dx = size.width / (PerfMonitor.historyLength - 1);
    final start = PerfMonitor.historyLength - v.length;
    for (var i = 0; i < v.length; i++) {
      final x = (start + i) * dx;
      final y = size.height - (v[i] / maxV) * size.height;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(path, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => true;
}

/// Bảng tổng kết 1 phiên ghi + nút copy (dùng chung cho overlay và màn hình Lab).
Future<void> showPerfReportDialog(BuildContext context, PerfReport r) {
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Kết quả đo'),
      content: SingleChildScrollView(
        child: SelectableText(r.summary(), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: r.summary()));
            ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(const SnackBar(content: Text('Đã copy tổng kết')));
          },
          child: const Text('Copy tổng kết'),
        ),
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: r.toCsv()));
            ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(const SnackBar(content: Text('Đã copy CSV (dán vào Excel)')));
          },
          child: const Text('Copy CSV'),
        ),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
      ],
    ),
  );
}
