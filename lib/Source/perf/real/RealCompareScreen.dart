// Đường dẫn: lib/Source/perf/real/RealCompareScreen.dart
//
// MÀN "SO SÁNH TRÊN APP THẬT" (Hồ sơ > Hiệu năng & Demo > SO SÁNH TRÊN APP THẬT)
//
//  1. Dữ liệu thật trong DB: số khu trọ / phòng / khách / hóa đơn / thẻ đang có.
//  2. TỰ ĐỘNG: chọn các màn hình thật rồi bấm Chạy. App tự mở từng màn ở cả 2 chế độ,
//     đo thời gian mở + tự cuộn + ghi FPS/RAM mỗi giây.
//  3. THỦ CÔNG: chọn chế độ (CHƯA / ĐÃ tối ưu), chọn màn hình, bấm "Bắt đầu ghi" rồi tự dùng app.
//     Bấm ■ STOP trên bảng FPS để lưu. Làm lại với chế độ còn lại để có cặp so sánh.
//  4. KẾT QUẢ: với mỗi màn hình, lấy lần đo mới nhất của mỗi chế độ và vẽ:
//     biểu đồ cột từng chỉ số, biểu đồ đường FPS / RAM / RAM ảnh theo thời gian, bảng số liệu.
//     Có biểu đồ tổng quan cho mọi màn. Copy Markdown / CSV để đưa vào báo cáo.
//     Chỉ hiện lần đo mới nhất + thẻ KẾT LUẬN + PHÂN TÍCH chi tiết (BenchAnalysis.dart).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qlpt_frontend/Source/api/Demo/DemoAPI.dart';

import '../PerfFlags.dart';
import 'BenchAnalysis.dart';
import 'BenchCharts.dart';
import 'RealBench.dart';
import 'RestartBench.dart';

class RealCompareScreen extends StatefulWidget {
  const RealCompareScreen({super.key});

  @override
  State<RealCompareScreen> createState() => RealCompareScreenState();
}

class RealCompareScreenState extends State<RealCompareScreen> {
  final Set<String> _selected = {for (final s in realScreens) s.id};
  int _scrollSeconds = 10;
  RealScreen? _manualScreen = realScreens.first;
  Map<String, dynamic>? _dbStats;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final s = await DemoAPI.stats(); // Đếm bản ghi thật trong các bảng của database
      if (mounted) setState(() => _dbStats = s);
    } catch (_) {}
  }

  /// Chạy đo tự động (gọi được từ integration test).
  Future<void> runAuto({List<RealScreen>? screens, int? seconds}) => RealBench.runAuto(
        Navigator.of(context),
        screens ?? realScreens.where((s) => _selected.contains(s.id)).toList(),
        scrollSeconds: seconds ?? _scrollSeconds,
      );

  void _copy(String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã copy $what')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('So sánh trên app thật', style: TextStyle(fontSize: 17)),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'md':
                  _copy(RealBench.markdown(), 'bảng Markdown');
                case 'csv':
                  _copy(RealBench.csv(), 'CSV (dán vào Excel để vẽ lại biểu đồ)');
                case 'clear':
                  await RealBench.clear();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'md', child: Text('Copy bảng + phân tích (Markdown)')),
              PopupMenuItem(value: 'csv', child: Text('Copy CSV FPS/RAM theo giây')),
              PopupMenuItem(value: 'clear', child: Text('Xóa kết quả')),
            ],
          ),
        ],
      ),
      body: ValueListenableBuilder<List<BenchRun>>(
        valueListenable: RealBench.runs,
        builder: (context, runs, _) => ListView(padding: const EdgeInsets.all(12), children: [
          _dataCard(),
          _restartCard(),
          _autoCard(),
          _manualCard(),
          ..._results(),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- Dữ liệu thật
  Widget _dataCard() {
    final s = _dbStats;
    return Card(
      color: Colors.indigo.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${PerfFlags.buildLabel} · cấu hình hiện tại: ${PerfFlags.modeLabel}', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Dữ liệu thật trong database (tài khoản đang đăng nhập):', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 4),
          if (s == null)
            const Text('Đang đếm...', style: TextStyle(fontSize: 12, color: Colors.grey))
          else
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in {
                'Khu trọ': s['properties'],
                'Phòng': s['rooms'],
                'Khách thuê': s['tenants'],
                'Hóa đơn': s['invoices'],
                'Thẻ': s['cards'],
                'Lượt quẹt thẻ': s['accessLogs'],
              }.entries)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('${e.key}: ${_n(e.value)}', style: const TextStyle(fontSize: 12)),
                ),
            ]),
        ]),
      ),
    );
  }

  static String _n(dynamic v) {
    final s = '${v ?? 0}';
    return s.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.');
  }

  // ---------------------------------------------------------------- Tắt hẳn app rồi bật lại
  RealScreen _restartScreen = realScreens[1]; // mặc định: Dịch vụ

  Widget _restartCard() {
    return Card(
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('0. TẮT HẲN APP RỒI BẬT LẠI (trực quan nhất)', style: TextStyle(fontWeight: FontWeight.bold)),
          const Text(
              'App tự tắt hẳn (mất toàn bộ RAM) rồi tự bật lại, tự vào màn được chọn và đo từ lúc bấm tới khi THẤY DỮ LIỆU, '
              'rồi tự cuộn. Giống người dùng vuốt tắt app rồi mở lại. Không cần đăng nhập lại.',
              style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade800),
              onPressed: _selected.isEmpty
                  ? null
                  : () => RestartBench.startAuto(
                      Navigator.of(context), realScreens.where((s) => _selected.contains(s.id)).toList(),
                      scrollSeconds: _scrollSeconds),
              icon: const Icon(Icons.restart_alt),
              label: Text('Tự động: ${_selected.length} màn × 2 chế độ (tắt/bật ${_selected.length * 2} lần)'),
            ),
          ),
          const Text('Chọn màn ở mục 1 bên dưới. Đừng chạm máy khi đang chạy, bấm "Hủy" ở dải đen để dừng.',
              style: TextStyle(fontSize: 11, color: Colors.black54)),
          const Divider(),
          const Text('Thủ công từng lượt:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          DropdownButton<RealScreen>(
            isExpanded: true,
            value: _restartScreen,
            items: [for (final s in realScreens) DropdownMenuItem(value: s, child: Text(s.name, style: const TextStyle(fontSize: 13)))],
            onChanged: (v) => setState(() => _restartScreen = v!),
          ),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: kBeforeColor),
                onPressed: () => RestartBench.startOne(_restartScreen, false, scrollSeconds: _scrollSeconds),
                child: const Text('Tắt/bật – CHƯA tối ưu', textAlign: TextAlign.center),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: kAfterColor),
                onPressed: () => RestartBench.startOne(_restartScreen, true, scrollSeconds: _scrollSeconds),
                child: const Text('Tắt/bật – ĐÃ tối ưu', textAlign: TextAlign.center),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- Tự động
  Widget _autoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ValueListenableBuilder<String?>(
          valueListenable: RealBench.status,
          builder: (context, status, _) {
            final busy = status != null;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('1. ĐO TỰ ĐỘNG (không tắt app)', style: TextStyle(fontWeight: FontWeight.bold)),
              const Text('Mỗi màn chạy 2 lượt (ĐÃ tối ưu rồi CHƯA tối ưu). Mỗi lượt: xóa cache, mở màn thật, '
                  'đo thời gian tới khi danh sách hiện, tự cuộn và ghi FPS/RAM mỗi giây. Đừng chạm màn hình khi đang đo.',
                  style: TextStyle(fontSize: 12)),
              for (final s in realScreens)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: _selected.contains(s.id),
                  onChanged: busy ? null : (v) => setState(() => v! ? _selected.add(s.id) : _selected.remove(s.id)),
                  title: Text(s.name, style: const TextStyle(fontSize: 13)),
                  subtitle: Text(s.techniques, style: const TextStyle(fontSize: 11)),
                ),
              Row(children: [
                const Text('Thời gian cuộn mỗi lượt: ', style: TextStyle(fontSize: 12)),
                DropdownButton<int>(
                  value: _scrollSeconds,
                  items: [for (final v in [5, 10, 15, 20, 30]) DropdownMenuItem(value: v, child: Text('$v giây'))],
                  onChanged: busy ? null : (v) => setState(() => _scrollSeconds = v!),
                ),
              ]),
              if (busy)
                Row(children: [
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(status, style: const TextStyle(fontSize: 12))),
                  TextButton(onPressed: RealBench.cancel, child: const Text('Dừng')),
                ])
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _selected.isEmpty ? null : () => runAuto(),
                    icon: const Icon(Icons.play_arrow),
                    label: Text('Chạy tự động ${_selected.length} màn × 2 chế độ'),
                  ),
                ),
            ]);
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- Thủ công
  Widget _manualCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: AnimatedBuilder(
          animation: PerfFlags.changes,
          builder: (context, _) {
            final mode = BenchMode.current();
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('2. ĐO THỦ CÔNG (tự thao tác trên app)', style: TextStyle(fontWeight: FontWeight.bold)),
              const Text(
                  'B1: chọn chế độ. B2: chọn màn hình, hoặc "Tự do" để tự đi khắp app. B3: bấm "Bắt đầu ghi" rồi '
                  'cuộn, bấm, mở chi tiết như người dùng thật. B4: bấm ■ STOP trên bảng FPS để lưu. '
                  'Làm lại với chế độ còn lại, kết quả tự ghép thành cặp so sánh bên dưới.',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('CHƯA tối ưu'), icon: Icon(Icons.close)),
                  ButtonSegment(value: true, label: Text('ĐÃ tối ưu'), icon: Icon(Icons.check)),
                ],
                selected: {if (mode == BenchMode.after) true else if (mode == BenchMode.before) false},
                emptySelectionAllowed: true,
                onSelectionChanged: (v) {
                  if (v.isNotEmpty) PerfFlags.setAllOptimizations(v.first);
                },
              ),
              if (mode == BenchMode.mixed)
                const Text('Đang bật/tắt lẻ từng kỹ thuật: lần ghi sẽ lưu là "Tùy chỉnh", không vào cặp so sánh.',
                    style: TextStyle(fontSize: 11, color: Colors.deepOrange)),
              const SizedBox(height: 6),
              DropdownButton<RealScreen?>(
                isExpanded: true,
                value: _manualScreen,
                items: [
                  for (final s in realScreens) DropdownMenuItem(value: s, child: Text(s.name, style: const TextStyle(fontSize: 13))),
                  const DropdownMenuItem(value: null, child: Text('Tự do: tự đi khắp app', style: TextStyle(fontSize: 13))),
                ],
                onChanged: (v) => setState(() => _manualScreen = v),
              ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.fiber_manual_record, color: Colors.red),
                  label: Text('Bắt đầu ghi – ${mode.label}'),
                  onPressed: () async {
                    await RealBench.startManual(Navigator.of(context), _manualScreen);
                    if (_manualScreen == null && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Đang ghi. Thoát ra dùng app bình thường, xong bấm ■ STOP trên bảng FPS.')));
                    }
                  },
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- Kết quả + biểu đồ
  List<Widget> _results() {
    final pairs = RealBench.pairs();
    final complete = pairs.where((p) => p.complete).toList();
    if (pairs.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Chưa có kết quả. Chạy đo tự động hoặc ghi thủ công ở cả 2 chế độ.', textAlign: TextAlign.center),
        ),
      ];
    }
    return [
      const Padding(
        padding: EdgeInsets.fromLTRB(4, 12, 4, 4),
        child: Text('KẾT QUẢ LẦN ĐO MỚI NHẤT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      ),
      if (complete.isNotEmpty) _conclusion(complete),
      if (complete.length >= 2) _overview(complete),
      for (final p in pairs) _pairCard(p),
    ];
  }

  Widget _overview(List<BenchPair> ps) {
    // Nhãn ngắn: "Dịch vụ ⟳" = đo bằng tắt/bật app, "Dịch vụ" = đo trong app
    String label(BenchPair p) => p.screen.split(' (').first + (p.screen.endsWith('tắt/bật app') ? ' ⟳' : '');
    (String, double, double) item(BenchPair p, double Function(BenchRun r) f) => (label(p), f(p.before!), f(p.after!));
    final timed = ps.where((p) => p.before!.openMs != null && p.after!.openMs != null).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Tổng quan mọi màn hình', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const ChartLegend(),
          const SizedBox(height: 10),
          const Text('⟳ = tắt hẳn app rồi bật lại', style: TextStyle(fontSize: 11, color: Colors.black54)),
          const SizedBox(height: 6),
          if (timed.isNotEmpty) ...[
            // TỐC ĐỘ là ưu tiên số 1 -> biểu đồ đầu tiên
            OverviewBarChart(title: 'Thời gian tới khi THẤY DỮ LIỆU', unit: 'ms, thấp hơn là tốt', items: [
              for (final p in timed) item(p, (r) => r.openMs!.toDouble()),
            ]),
            const Divider(height: 24),
          ],
          OverviewBarChart(title: 'FPS trung bình khi cuộn', unit: 'cao hơn là tốt', items: [for (final p in ps) item(p, (r) => r.avgFps)]),
          const Divider(height: 24),
          OverviewBarChart(title: 'Khung hình giật', unit: '%, thấp hơn là tốt', items: [for (final p in ps) item(p, (r) => r.jankPct)]),
          const Divider(height: 24),
          OverviewBarChart(title: 'RAM cao nhất', unit: 'MB, thấp hơn là tốt', items: [for (final p in ps) item(p, (r) => r.maxRss)]),
        ]),
      ),
    );
  }

  Widget _pairCard(BenchPair p) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.screen, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 2),
          for (final r in [p.before, p.after])
            if (r != null)
              Text('${r.mode.label}: ${r.sourceLabel}, ${_time(r.at)}, ghi ${r.seconds}s · ${r.build}',
                  style: TextStyle(fontSize: 11, color: r.mode == BenchMode.before ? kBeforeColor : kAfterColor)),
          if (!p.complete)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  'Còn thiếu lần đo ${p.before == null ? 'CHƯA tối ưu' : 'ĐÃ tối ưu'} để so sánh. Lượt đó không thấy dữ liệu sau '
                  '150 giây hoặc app bị máy tắt (thường do máy thiếu RAM). Đo lại riêng lượt này bằng nút "Tắt/bật" thủ công.',
                  style: const TextStyle(fontSize: 12, color: Colors.deepOrange)),
            )
          else ...[
            const SizedBox(height: 8),
            const ChartLegend(),
            const SizedBox(height: 8),
            CompareBarChart(metrics: p.metrics),
            const Divider(height: 20),
            const Text('PHÂN TÍCH', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            const SizedBox(height: 6),
            AnalysisView(pair: p),
            const Divider(),
            CompareLineChart(
                title: 'FPS theo thời gian',
                unit: 'FPS',
                before: p.before!.fpsSeries,
                after: p.after!.fpsSeries,
                refLine: 60,
                refLabel: '60 FPS'),
            const SizedBox(height: 12),
            CompareLineChart(title: 'RAM của app (RSS) theo thời gian', unit: 'MB', before: p.before!.rssSeries, after: p.after!.rssSeries),
            if (p.before!.imageSeries.any((v) => v > 0.5) || p.after!.imageSeries.any((v) => v > 0.5)) ...[
              const SizedBox(height: 12),
              CompareLineChart(title: 'RAM ảnh đã giải mã', unit: 'MB', before: p.before!.imageSeries, after: p.after!.imageSeries),
            ],
            const Divider(),
            _table(p.metrics),
          ],
        ]),
      ),
    );
  }

  Widget _table(List<CompareMetric> ms) {
    const h = TextStyle(fontSize: 11, fontWeight: FontWeight.bold);
    const c = TextStyle(fontSize: 11);
    Widget cell(String s, [TextStyle st = c]) => Padding(padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2), child: Text(s, style: st));
    return Table(
      columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(1.1), 2: FlexColumnWidth(1.1), 3: FlexColumnWidth(1.3)},
      border: TableBorder(horizontalInside: BorderSide(color: Colors.grey.shade200)),
      children: [
        TableRow(children: [cell('Chỉ số', h), cell('Chưa tối ưu', h), cell('Đã tối ưu', h), cell('Kết quả', h)]),
        for (final m in ms)
          TableRow(children: [
            cell(m.name),
            cell(m.fmt(m.before)),
            cell(m.fmt(m.after)),
            cell(m.gainStr, TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: m.better ? kAfterColor : Colors.grey.shade700)),
          ]),
      ],
    );
  }

  // ---------------------------------------------------------------- Kết luận (đọc to khi trình bày)
  Widget _conclusion(List<BenchPair> ps) {
    return Card(
      color: const Color(0xFFE8F5E9),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.emoji_events, color: kAfterColor, size: 20),
            SizedBox(width: 6),
            Text('KẾT LUẬN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ]),
          const SizedBox(height: 6),
          for (final p in ps)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('✓  ', style: TextStyle(color: kAfterColor, fontWeight: FontWeight.bold)),
                Expanded(child: Text(BenchAnalysis.headline(p), style: const TextStyle(fontSize: 13, height: 1.35))),
              ]),
            ),
          const SizedBox(height: 2),
          const Text('Chi tiết từng màn + giải thích vì sao ở các thẻ bên dưới.', style: TextStyle(fontSize: 11, color: Colors.black54)),
        ]),
      ),
    );
  }

  static String _time(DateTime d) =>
      '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';
}
