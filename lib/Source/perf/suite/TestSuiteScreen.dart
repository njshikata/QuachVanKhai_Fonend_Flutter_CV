// Đường dẫn: lib/Source/perf/suite/TestSuiteScreen.dart
//
// MÀN "BỘ TEST TỐI ƯU" (mở từ: Hồ sơ > Hiệu năng & Demo > BỘ TEST TỐI ƯU)
//  - Mỗi kỹ thuật 1 thẻ: mô tả kỹ thuật, file code, nút "Chạy" -> tự đo CHƯA tối ưu vs ĐÃ tối ưu, hiện bảng.
//  - Nút "Chạy test tổng thể": chạy lần lượt T1..T8, cuối cùng hiện bảng tổng hợp.
//  - Nút "Copy Markdown": copy toàn bộ kết quả để dán thẳng vào báo cáo (đồng thời in ra console với tiền tố [SUITE]).
// Logic đo nằm ở OptimizationTests.dart.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../PerfFlags.dart';
import 'OptimizationTests.dart';

class TestSuiteScreen extends StatefulWidget {
  const TestSuiteScreen({super.key});

  @override
  State<TestSuiteScreen> createState() => TestSuiteScreenState();
}

class TestSuiteScreenState extends State<TestSuiteScreen> {
  // static: thoát màn hình vào lại vẫn còn kết quả
  static final Map<String, TestResult> _results = {};
  String? _status;
  bool _busy = false;
  DateTime? _overallAt;

  Map<String, TestResult> get results => _results;
  bool get busy => _busy;

  Future<void> _runOne(OptimizationTest t) async {
    final ctx = TestContext(Navigator.of(context), (s) {
      if (mounted) setState(() => _status = s);
    });
    final sw = Stopwatch()..start();
    TestResult r;
    try {
      r = await t.run(ctx);
      r = TestResult(t, metrics: r.metrics, checks: r.checks, error: r.error, took: sw.elapsed);
    } catch (e) {
      r = TestResult(t, error: e.toString(), took: sw.elapsed);
    }
    debugPrint('[SUITE] ${t.id} ${r.passed ? 'DAT' : 'KHONG DAT'} – ${r.headline}');
    if (mounted) setState(() => _results[t.id] = r);
  }

  Future<void> _guard(Future<void> Function() fn) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await fn();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
  }

  /// Chạy 1 bài test.
  Future<void> runTest(OptimizationTest t) => _guard(() => _runOne(t));

  /// TEST TỔNG THỂ: chạy hết T1..T8 rồi hiện bảng tổng hợp.
  Future<void> runAll() => _guard(() async {
        _results.clear();
        for (final t in allOptimizationTests) {
          if (!mounted) return;
          await _runOne(t);
        }
        _overallAt = DateTime.now();
        debugPrint(markdown());
        if (mounted) _showSummary();
      });

  /// Toàn bộ kết quả dạng Markdown (dán vào báo cáo).
  String markdown() {
    final b = StringBuffer('## Kết quả bộ test tối ưu – ${PerfFlags.buildLabel}\n\n');
    b.writeln('Thời điểm: ${_overallAt ?? DateTime.now()}\n');
    b.writeln('| Test | Kỹ thuật | Kết quả | Chỉ số chính |');
    b.writeln('|---|---|---|---|');
    for (final t in allOptimizationTests) {
      final r = _results[t.id];
      b.writeln('| ${t.id} | ${t.title} | ${r == null ? 'chưa chạy' : (r.passed ? 'ĐẠT' : 'KHÔNG ĐẠT')} | ${r?.headline ?? ''} |');
    }
    b.writeln();
    for (final t in allOptimizationTests) {
      final r = _results[t.id];
      if (r != null) b.writeln(r.toMarkdown());
    }
    return b.toString();
  }

  void _copy() {
    final md = markdown();
    Clipboard.setData(ClipboardData(text: md));
    for (final line in md.split('\n')) {
      debugPrint('[SUITE] $line');
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã copy bảng kết quả (Markdown)')));
  }

  void _showSummary() {
    final passed = _results.values.where((r) => r.passed).length;
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Test tổng thể: $passed/${_results.length} đạt'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final t in allOptimizationTests)
              if (_results[t.id] case final r?)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(r.passed ? Icons.check_circle : Icons.cancel, color: r.passed ? Colors.green : Colors.red),
                  title: Text('${t.id}. ${t.title}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text(r.headline, style: const TextStyle(fontSize: 12)),
                ),
          ]),
        ),
        actions: [
          TextButton(onPressed: _copy, child: const Text('Copy Markdown')),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Đóng')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bộ test tối ưu', style: TextStyle(fontSize: 17)),
        actions: [
          IconButton(tooltip: 'Copy Markdown', onPressed: _results.isEmpty ? null : _copy, icon: const Icon(Icons.copy)),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Card(
          color: Colors.indigo.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Đang chạy: ${PerfFlags.buildLabel} · cấu hình hiện tại: ${PerfFlags.modeLabel}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text(
                'Mỗi bài test tự chạy cùng 1 tình huống 2 lần: tắt kỹ thuật (CHƯA tối ưu) rồi bật (ĐÃ tối ưu), '
                'dùng chính code của app. Công tắc chỉ đổi tạm, xong trả lại như cũ. '
                'Cần đăng nhập tài khoản CHỦ TRỌ và server đang chạy. Đừng chạm màn hình khi đang đo.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : runAll,
                  icon: const Icon(Icons.playlist_play),
                  label: const Text('Chạy test tổng thể (T1–T8, ~3 phút)'),
                ),
              ),
              if (_status != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_status!, style: const TextStyle(fontSize: 12))),
                  ]),
                ),
            ]),
          ),
        ),
        for (final t in allOptimizationTests) _testCard(t),
      ]),
    );
  }

  Widget _testCard(OptimizationTest t) {
    final r = _results[t.id];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: r == null ? Colors.grey.shade300 : (r.passed ? Colors.green : Colors.red),
              child: Text(t.id, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(t.title, style: const TextStyle(fontWeight: FontWeight.bold))),
            OutlinedButton(onPressed: _busy ? null : () => runTest(t), child: Text(r == null ? 'Chạy' : 'Chạy lại')),
          ]),
          const SizedBox(height: 6),
          Text(t.description, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 4),
          Text(t.codeRef, style: TextStyle(fontSize: 11, color: Colors.indigo.shade400, fontFamily: 'monospace')),
          if (r != null) ...[const Divider(), _resultView(r)],
        ]),
      ),
    );
  }

  Widget _resultView(TestResult r) {
    if (r.error != null) return Text('Lỗi: ${r.error}', style: const TextStyle(color: Colors.red, fontSize: 12));
    const head = TextStyle(fontWeight: FontWeight.bold, fontSize: 12);
    const cell = TextStyle(fontSize: 12);
    Widget c(String s, [TextStyle st = cell]) => Padding(padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2), child: Text(s, style: st));

    if (r.checks.isNotEmpty) {
      return Column(children: [
        for (final k in r.checks)
          Row(children: [
            Icon(k.ok ? Icons.check_circle : Icons.cancel, size: 16, color: k.ok ? Colors.green : Colors.red),
            const SizedBox(width: 6),
            Expanded(child: Text(k.name, style: cell)),
            Text(k.detail, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
          ]),
      ]);
    }
    return Table(
      columnWidths: const {0: FlexColumnWidth(2.2), 1: FlexColumnWidth(1.2), 2: FlexColumnWidth(1.2), 3: FlexColumnWidth(0.9)},
      children: [
        TableRow(children: [c('Chỉ số', head), c('Chưa tối ưu', head), c('Đã tối ưu', head), c('Cải thiện', head)]),
        for (final m in r.metrics)
          TableRow(
            decoration: m.key ? BoxDecoration(color: Colors.amber.shade50) : null,
            children: [
              c(m.name, m.key ? head : cell),
              c(m.beforeStr),
              c(m.afterStr),
              c(m.gainStr, TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: (m.gain ?? 1) >= 1.1 ? Colors.green : Colors.orange)),
            ],
          ),
      ],
    );
  }
}
