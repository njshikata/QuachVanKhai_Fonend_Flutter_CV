// Đường dẫn: lib/Source/perf/MeterGalleryScreen.dart
//
// THƯ VIỆN ẢNH CÔNG TƠ (DEMO) – lưới rất nhiều ảnh, nơi thấy rõ nhất tác dụng tối ưu ảnh ở phía app.
// Ảnh lấy từ API demo có sẵn của server (/api/landlord/demo/img/{id}, JPEG gốc 1600x1200 ~60KB,
// thêm ?w=300 thì server trả bản thu nhỏ ~6KB). Không cần sửa backend.
//
// Mỗi công tắc trong "Hiệu năng & Demo" có tác dụng ở đây (chốt lúc mở màn hình):
//  - Phân trang:          bật = tải 60 ảnh/trang khi cuộn gần cuối | tắt = tải JSON của TẤT CẢ ảnh một lần
//  - compute() JSON:      bật = parse JSON ở isolate (không đứng UI) | tắt = parse trên UI thread
//  - Ảnh thu nhỏ:         bật = xin ảnh 300px + giải mã đúng kích thước ô | tắt = tải & giải mã ảnh gốc 1600px
//  - Cache ảnh ra đĩa:    bật = cached_network_image | tắt = Image.network (mở lại là tải lại)
//  - ETag + SQLite:       danh sách ảnh đi qua SyncedApi
// Lưới LUÔN dùng GridView.builder (kể cả bản không tối ưu): build cùng lúc hàng nghìn ảnh gốc 1600px
// sẽ làm app văng vì hết RAM -> không đo được gì.
//
// Nút "Tự so sánh": tự chạy 2 lượt (KHÔNG tối ưu rồi TỐI ƯU), mỗi lượt xóa sạch cache cho công bằng,
// đo thời gian tải + hiện đủ ảnh màn đầu, rồi tự cuộn 12 giây ghi FPS/RAM -> bảng so sánh. Xong trả lại công tắc như cũ.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qlpt_frontend/Source/api/Demo/DemoAPI.dart';
import 'package:qlpt_frontend/Source/api/SyncedApi.dart';
import 'package:qlpt_frontend/Source/cache/AppCacheManager.dart';
import 'package:qlpt_frontend/Source/cache/AppNetworkImage.dart';

import 'PerfFlags.dart';
import 'PerfMonitor.dart';

class MeterGalleryScreen extends StatefulWidget {
  final int total;

  const MeterGalleryScreen({super.key, this.total = 1000});

  @override
  State<MeterGalleryScreen> createState() => _MeterGalleryScreenState();
}

class _RunResult {
  final bool optimized;
  int? jsonMs;
  int? firstScreenMs;
  bool timedOut = false;
  int loaded = 0;
  int errors = 0;
  PerfReport? report;

  _RunResult(this.optimized);
}

class _MeterGalleryScreenState extends State<MeterGalleryScreen> {
  static const Duration scrollDuration = Duration(seconds: 12);
  static const Duration stepTimeout = Duration(seconds: 45);

  GlobalKey<_MeterGridState> _gridKey = GlobalKey();
  bool _comparing = false;
  String? _status;

  /// Xóa mọi cache (RAM + đĩa + SQLite) để lượt đo nào cũng bắt đầu "lạnh" như nhau.
  Future<void> _coldCaches() async {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    await AppCacheManager.instance.emptyCache();
    await SyncedApi.clear();
  }

  void _rebuildGrid() => setState(() => _gridKey = GlobalKey());

  Future<void> _autoScroll(_MeterGridState grid) async {
    final c = grid.controller;
    final sw = Stopwatch()..start();
    if (c.hasClients) c.jumpTo(0);
    while (mounted && sw.elapsed < scrollDuration) {
      if (!c.hasClients) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        continue;
      }
      final max = c.position.maxScrollExtent;
      final target = c.offset + 1250;
      if (max > 0 && target >= max && !grid.hasMore) {
        await c.animateTo(max, duration: const Duration(milliseconds: 300), curve: Curves.linear);
        c.jumpTo(0); // Hết danh sách -> lên đầu, cuộn tiếp
        continue;
      }
      await c.animateTo(target.clamp(0, max > 0 ? max : target).toDouble(),
          duration: const Duration(milliseconds: 500), curve: Curves.linear);
    }
  }

  Future<void> _autoCompare() async {
    if (_comparing) return;
    final saved = {for (final f in PerfFlags.optimizations) f: f.value};
    final wasOverlay = PerfFlags.showOverlay.value;
    final results = <_RunResult>[];
    setState(() => _comparing = true);
    try {
      // Đo bản TỐI ƯU trước: bản không tối ưu để lại hàng trăm ảnh gốc 1600px vẫn đang tải/giải mã ngầm
      // sau khi đóng lưới -> nếu đo sau nó, lượt tối ưu bị chậm oan.
      for (final optimized in [true, false]) {
        final r = _RunResult(optimized);
        final name = optimized ? 'TỐI ƯU' : 'KHÔNG tối ưu';
        setState(() => _status = 'Lượt ${results.length + 1}/2 – $name: xóa cache...');
        await PerfFlags.setAllOptimizations(optimized);
        await _coldCaches();
        await Future<void>.delayed(const Duration(seconds: 3)); // Cho mạng/CPU nghỉ giữa 2 lượt
        if (!mounted) return;
        _rebuildGrid(); // Màn lưới mới, chốt cấu hình vừa đặt
        await WidgetsBinding.instance.endOfFrame;
        final grid = _gridKey.currentState;
        if (grid == null) return;

        setState(() => _status = 'Lượt ${results.length + 1}/2 – $name: đang tải ảnh...');
        final sw = Stopwatch()..start();
        try {
          await grid.dataLoaded.future.timeout(stepTimeout);
          r.jsonMs = grid.jsonMs;
          await grid.firstScreen.future.timeout(stepTimeout);
          r.firstScreenMs = sw.elapsedMilliseconds;
        } on TimeoutException {
          r.timedOut = true;
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));

        setState(() => _status = 'Lượt ${results.length + 1}/2 – $name: tự cuộn ${scrollDuration.inSeconds}s...');
        PerfMonitor.instance.startRecording('Ảnh công tơ – $name');
        await _autoScroll(grid);
        r.report = PerfMonitor.instance.stopRecording();
        r.loaded = grid.loadedCount;
        r.errors = grid.errorCount;
        results.add(r);
        if (!mounted) return;
      }
    } finally {
      for (final e in saved.entries) {
        await PerfFlags.set(e.key, e.value);
      }
      if (!wasOverlay && !PerfFlags.showOverlay.value) PerfMonitor.instance.stop();
      if (mounted) {
        setState(() {
          _comparing = false;
          _status = null;
        });
        _rebuildGrid();
      }
    }
    if (mounted && results.length == 2) {
      final before = results.firstWhere((r) => !r.optimized);
      final after = results.firstWhere((r) => r.optimized);
      await showDialog<void>(context: context, builder: (_) => _CompareDialog(before, after, widget.total));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ảnh công tơ (demo)'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: AnimatedBuilder(
            animation: PerfFlags.changes,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('${widget.total} ảnh · ${PerfFlags.modeLabel}',
                  style: TextStyle(
                      color: PerfFlags.allOptimized ? Colors.green : Colors.deepOrange, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Tải lại (giữ cache)',
            onPressed: _comparing ? null : _rebuildGrid,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _comparing ? null : _autoCompare,
        icon: _comparing
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.compare_arrows),
        label: Text(_comparing ? 'Đang so sánh...' : 'Tự so sánh'),
      ),
      body: Stack(
        children: [
          _MeterGrid(key: _gridKey, total: widget.total),
          if (_status != null)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Material(
                color: Colors.black87,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(_status!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// =====================================================================
// LƯỚI ẢNH
// =====================================================================
class _MeterGrid extends StatefulWidget {
  final int total;

  const _MeterGrid({super.key, required this.total});

  @override
  State<_MeterGrid> createState() => _MeterGridState();
}

class _MeterGridState extends State<_MeterGrid> {
  static const int pageSize = 60;
  static const int columns = 3;
  static const int firstScreenCount = 12; // 4 hàng đầu

  // Chốt cấu hình lúc mở
  final bool _usePaging = PerfFlags.paging.value;
  final bool _thumb = PerfFlags.imageResize.value;

  final controller = ScrollController();
  final List<DemoItem> _items = [];
  final Completer<void> dataLoaded = Completer();
  final Completer<void> firstScreen = Completer();
  final Set<int> _settled = {};
  int? jsonMs;
  int loadedCount = 0;
  int errorCount = 0;
  int _page = 0;
  bool hasMore = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_usePaging || !controller.hasClients) return;
    if (controller.position.extentAfter < 800) _load();
  }

  Future<void> _load() async {
    if (_loading || !hasMore) return;
    _loading = true;
    final sw = Stopwatch()..start();
    try {
      final r = _usePaging
          ? await DemoAPI.feed(_page, pageSize, widget.total)
          : await DemoAPI.feed(0, 0, widget.total); // size 0 = server trả TẤT CẢ trong 1 lần
      if (!mounted) return;
      setState(() {
        _items.addAll(r.items);
        _page++;
        hasMore = _usePaging && r.hasNext;
      });
      if (!dataLoaded.isCompleted) {
        jsonMs = sw.elapsedMilliseconds;
        dataLoaded.complete();
        if (_items.isEmpty && !firstScreen.isCompleted) firstScreen.complete();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceAll('Exception: ', ''));
      if (!dataLoaded.isCompleted) dataLoaded.completeError(e);
    } finally {
      _loading = false;
    }
  }

  void _onSettled(int index, bool ok) {
    if (!_settled.add(index)) return;
    ok ? loadedCount++ : errorCount++;
    if (!firstScreen.isCompleted) {
      final need = _items.length < firstScreenCount ? _items.length : firstScreenCount;
      var all = true;
      for (var i = 0; i < need; i++) {
        if (!_settled.contains(i)) {
          all = false;
          break;
        }
      }
      if (all) firstScreen.complete();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Lỗi tải danh sách ảnh: $_error\n(Cần tài khoản CHỦ TRỌ)', textAlign: TextAlign.center),
        ),
      );
    }
    if (_items.isEmpty) return const Center(child: CircularProgressIndicator());

    return LayoutBuilder(builder: (context, box) {
      const spacing = 4.0;
      final tile = (box.maxWidth - spacing * (columns + 1)) / columns;
      return GridView.builder(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(spacing, spacing, spacing, 96),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
          mainAxisExtent: tile + 34,
        ),
        itemCount: _items.length + (hasMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= _items.length) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          final item = _items[i];
          return _MeterTile(
            item: item,
            size: tile,
            // Bản tối ưu: ảnh 300px (~6KB) cho ô ~120dp. Bản không tối ưu: ảnh gốc 1600px (~60KB).
            url: _thumb ? '${item.imageUrl}?w=300' : item.imageUrl,
            onSettled: (ok) => _onSettled(i, ok),
          );
        },
      );
    });
  }
}

Widget _placeholder(BuildContext context) => const ColoredBox(color: Color(0xFFE0E0E0));

class _MeterTile extends StatelessWidget {
  final DemoItem item;
  final double size;
  final String url;
  final void Function(bool ok) onSettled;

  const _MeterTile({required this.item, required this.size, required this.url, required this.onSettled});

  @override
  Widget build(BuildContext context) {
    final paid = item.status == 'PAID';
    final created = DateTime.tryParse(item.createdAt);
    final cycle = created == null ? '' : '${created.month.toString().padLeft(2, '0')}/${created.year}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppNetworkImage(
          url: url,
          width: size,
          height: size,
          borderRadius: BorderRadius.circular(6),
          authenticated: false, // Ảnh demo public
          fallbackIcon: Icons.electric_meter,
          // Ô xám tĩnh thay vòng quay: hàng chục vòng quay cùng lúc khi cuộn nhanh làm GPU vẽ lại liên tục
          placeholder: _placeholder,
          onSettled: onSettled,
        ),
        const SizedBox(height: 2),
        Text(item.room, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        Text('#${item.id} · $cycle', maxLines: 1,
            style: TextStyle(fontSize: 10, color: paid ? Colors.green.shade700 : Colors.redAccent)),
      ],
    );
  }
}

// =====================================================================
// BẢNG SO SÁNH
// =====================================================================
class _CompareDialog extends StatelessWidget {
  final _RunResult before;
  final _RunResult after;
  final int total;

  const _CompareDialog(this.before, this.after, this.total);

  static String _ms(int? v, bool timedOut) => v == null ? (timedOut ? '> 45 s' : '–') : v >= 1000 ? '${(v / 1000).toStringAsFixed(1)} s' : '$v ms';

  /// Hệ số cải thiện: "nhỏ hơn là tốt" -> before/after, ngược lại after/before.
  static String _gain(double? b, double? a, {bool lowerIsBetter = true}) {
    if (b == null || a == null || a <= 0 || b <= 0) return '';
    final x = lowerIsBetter ? b / a : a / b;
    if (x >= 1.1) return '×${x.toStringAsFixed(x >= 10 ? 0 : 1)} tốt hơn';
    if (x <= 0.9) return 'kém hơn';
    return '≈';
  }

  @override
  Widget build(BuildContext context) {
    final b = before.report;
    final a = after.report;
    final rows = <List<String>>[
      ['Tải danh sách (JSON)', _ms(before.jsonMs, before.timedOut), _ms(after.jsonMs, after.timedOut),
        _gain(before.jsonMs?.toDouble(), after.jsonMs?.toDouble())],
      ['Hiện đủ 12 ảnh đầu', _ms(before.firstScreenMs, before.timedOut), _ms(after.firstScreenMs, after.timedOut),
        _gain((before.firstScreenMs ?? (before.timedOut ? 45000 : null))?.toDouble(), after.firstScreenMs?.toDouble())],
      ['FPS khi cuộn (TB)', b == null ? '–' : b.avgFps.toStringAsFixed(0), a == null ? '–' : a.avgFps.toStringAsFixed(0),
        _gain(b?.avgFps, a?.avgFps, lowerIsBetter: false)],
      ['FPS thấp nhất', b == null ? '–' : b.minFps.toStringAsFixed(0), a == null ? '–' : a.minFps.toStringAsFixed(0), ''],
      ['Khung hình giật', b == null ? '–' : '${b.jankPercent.toStringAsFixed(0)}%', a == null ? '–' : '${a.jankPercent.toStringAsFixed(0)}%',
        _gain(b?.jankPercent, a?.jankPercent)],
      ['Khung chậm nhất', b == null ? '–' : '${b.worstMs.toStringAsFixed(0)} ms', a == null ? '–' : '${a.worstMs.toStringAsFixed(0)} ms',
        _gain(b?.worstMs, a?.worstMs)],
      ['RAM app cao nhất', b == null || b.maxRss <= 0 ? '–' : '${b.maxRss.toStringAsFixed(0)} MB',
        a == null || a.maxRss <= 0 ? '–' : '${a.maxRss.toStringAsFixed(0)} MB', _gain(b?.maxRss, a?.maxRss)],
      ['RAM cache ảnh cao nhất', b == null ? '–' : '${b.maxImageMb.toStringAsFixed(0)} MB', a == null ? '–' : '${a.maxImageMb.toStringAsFixed(0)} MB',
        _gain(b?.maxImageMb, a?.maxImageMb)],
      ['Ảnh hiện được / lỗi', '${before.loaded} / ${before.errors}', '${after.loaded} / ${after.errors}', ''],
    ];

    TableRow row(List<String> c, {bool header = false}) => TableRow(
          decoration: BoxDecoration(color: header ? Colors.grey.shade200 : null),
          children: [
            for (var i = 0; i < c.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Text(c[i],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: header || i == 0 ? FontWeight.bold : FontWeight.normal,
                      color: header
                          ? Colors.black87
                          : i == 1
                              ? Colors.deepOrange
                              : i == 2
                                  ? Colors.green.shade700
                                  : i == 3
                                      ? Colors.blue
                                      : Colors.black87,
                    )),
              ),
          ],
        );

    return AlertDialog(
      title: const Text('So sánh: ảnh công tơ'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$total ảnh, mỗi lượt xóa sạch cache, tự cuộn ${_MeterGalleryScreenState.scrollDuration.inSeconds}s.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            Table(
              border: TableBorder.all(color: Colors.grey.shade300),
              columnWidths: const {0: FlexColumnWidth(1.6), 1: FlexColumnWidth(1.1), 2: FlexColumnWidth(1.1), 3: FlexColumnWidth(1.1)},
              children: [
                row(['', 'Không tối ưu', 'Tối ưu', 'Cải thiện'], header: true),
                for (final r in rows) row(r),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Bản không tối ưu: tải JSON tất cả ảnh 1 lần + parse trên UI thread, tải & giải mã ảnh gốc 1600px, không cache đĩa.\n'
              'Bản tối ưu: phân trang 60 ảnh, parse ở isolate, ảnh 300px giải mã đúng cỡ ô, cache đĩa.',
              style: TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Đóng'))],
    );
  }
}
