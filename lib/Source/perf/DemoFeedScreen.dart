// Đường dẫn: lib/Source/perf/DemoFeedScreen.dart
//
// DANH SÁCH DEMO RẤT DÀI (1.000 – 20.000 dòng, mỗi dòng 1 ảnh JPEG 1600x1200 từ server)
// dùng PagedListView thật của app -> mọi công tắc trong PerfFlags đều có tác dụng ở đây.
//  - Nút ▶ "Tự cuộn & đo": cuộn đều 15 giây + tự ghi FPS/RAM -> ra bảng kết quả (lặp lại được, công bằng khi so sánh).
//  - Nút ★ trên mỗi dòng: test "đổi 1 item" (ValueNotifier vs setState cả list) -> xem số "Item build" trên overlay.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qlpt_frontend/Source/api/Demo/DemoAPI.dart';
import 'package:qlpt_frontend/Source/api/SmartCard/SmartCardDTO.dart' show PageResult;
import 'package:qlpt_frontend/Source/cache/AppNetworkImage.dart';
import 'package:qlpt_frontend/Source/scr/Common/PagedListView.dart';

import 'PerfFlags.dart';
import 'PerfMonitor.dart';
import 'PerfOverlay.dart';

class DemoFeedScreen extends StatefulWidget {
  final int total;

  const DemoFeedScreen({super.key, required this.total});

  @override
  State<DemoFeedScreen> createState() => _DemoFeedScreenState();
}

class _DemoFeedScreenState extends State<DemoFeedScreen> {
  static const Duration benchDuration = Duration(seconds: 15);

  final _listKey = GlobalKey<PagedListViewState<DemoItem>>();
  bool _benchRunning = false;

  Future<PageResult<DemoItem>> _fetch(int page, int size) => DemoAPI.feed(page, size, widget.total);

  Future<void> _runBenchmark() async {
    final list = _listKey.currentState;
    if (list == null || _benchRunning) return;
    final c = list.scrollController;
    if (!c.hasClients) return;
    setState(() => _benchRunning = true);

    final wasOverlay = PerfFlags.showOverlay.value;
    PerfMonitor.instance.startRecording('Cuộn ${widget.total} dòng ${benchDuration.inSeconds}s');
    final sw = Stopwatch()..start();
    try {
      c.jumpTo(0);
      // Cuộn đều ~2500 px/giây (giống người dùng vuốt nhanh liên tục)
      while (mounted && sw.elapsed < benchDuration) {
        final target = c.offset + 1250;
        if (c.position.maxScrollExtent > 0 && target >= c.position.maxScrollExtent && !list.hasMore) {
          await c.animateTo(c.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.linear);
          c.jumpTo(0); // Hết danh sách -> quay lại đầu, tiếp tục đo
          continue;
        }
        await c.animateTo(target, duration: const Duration(milliseconds: 500), curve: Curves.linear);
      }
    } catch (_) {
      // Màn hình bị đóng giữa chừng
    } finally {
      final report = PerfMonitor.instance.stopRecording();
      if (!wasOverlay && !PerfFlags.showOverlay.value) PerfMonitor.instance.stop();
      if (mounted) {
        setState(() => _benchRunning = false);
        if (report != null) unawaited(showPerfReportDialog(context, report));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Demo ${widget.total} dòng'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(PerfFlags.modeLabel,
                style: TextStyle(
                    color: PerfFlags.allOptimized ? Colors.green : Colors.deepOrange, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _benchRunning ? null : _runBenchmark,
        icon: _benchRunning
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.speed),
        label: Text(_benchRunning ? 'Đang đo...' : 'Tự cuộn & đo ${benchDuration.inSeconds}s'),
      ),
      body: PagedListView<DemoItem>(
        key: _listKey,
        fetch: _fetch,
        pageSize: 20,
        unpagedPageSize: 0, // Tắt phân trang -> server trả TOÀN BỘ trong 1 lần
        itemExtent: 88,
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
        itemBuilder: (context, item, index) => ValueListenableBuilder<DemoItem>(
          valueListenable: item,
          builder: (context, d, _) => _DemoTile(item: d, onStar: () => item.value = d.toggleStar()),
        ),
      ),
    );
  }
}

class _DemoTile extends StatelessWidget {
  final DemoItem item;
  final VoidCallback onStar;

  const _DemoTile({required this.item, required this.onStar});

  @override
  Widget build(BuildContext context) {
    final paid = item.status == 'PAID';
    return SizedBox(
      height: 88,
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            const SizedBox(width: 8),
            AppNetworkImage(
              // TỐI ƯU ẢNH: xin server bản thu nhỏ 200px (~4KB) thay vì ảnh gốc 1600px (~60KB) cho ô 64px.
              // Tắt "memCacheWidth" trong Hiệu năng & Demo -> tải ảnh gốc để so sánh.
              url: PerfFlags.imageResize.value ? '${item.imageUrl}?w=200' : item.imageUrl,
              width: 64,
              height: 64,
              borderRadius: BorderRadius.circular(8),
              fallbackIcon: Icons.image,
              authenticated: false, // Ảnh demo public -> không cần JWT/handshake
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('#${item.id} ${item.title}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('${item.room} · ${item.area}m² · ${item.tags.join(', ')}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                  Text(item.description,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                ],
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${(item.amount / 1000).toStringAsFixed(0)}k',
                    style: TextStyle(color: paid ? Colors.green : Colors.redAccent, fontWeight: FontWeight.bold)),
                Text(paid ? 'Đã TT' : 'Chưa TT', style: const TextStyle(fontSize: 11)),
              ],
            ),
            IconButton(
              tooltip: 'Đổi trạng thái 1 dòng',
              icon: Icon(item.starred ? Icons.star : Icons.star_border, color: item.starred ? Colors.amber : Colors.grey),
              onPressed: onStar,
            ),
          ],
        ),
      ),
    );
  }
}
