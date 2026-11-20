// Đường dẫn: lib/Source/perf/PerfLabScreen.dart
//
// MÀN HÌNH "HIỆU NĂNG & DEMO" (vào từ Cài đặt)
//  1. Sinh / xóa dữ liệu demo trên server (hàng nghìn phòng, người thuê, hóa đơn, log thẻ).
//  2. Bật/tắt bảng FPS-RAM nổi.
//  3. Bật/tắt TỪNG kỹ thuật tối ưu để so sánh trước/sau.
//  4. Các bài đo có số liệu: cuộn danh sách dài, parse JSON (UI thread vs compute), tải lại (ETag 304).
//  5. Lưu kết quả -> copy dán vào báo cáo.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qlpt_frontend/Source/api/API_total.dart';
import 'package:qlpt_frontend/Source/api/Demo/DemoAPI.dart';
import 'package:qlpt_frontend/Source/api/SyncedApi.dart';
import 'package:qlpt_frontend/Source/cache/AppCacheManager.dart';
import 'package:qlpt_frontend/Source/security/Security.dart';

import 'DemoFeedScreen.dart';
import 'MeterGalleryScreen.dart';
import 'real/RealCompareScreen.dart';
import 'suite/TestSuiteScreen.dart';
import 'PerfFlags.dart';
import 'PerfMonitor.dart';
import 'PerfOverlay.dart';

// Top-level để chạy trong compute()
dynamic _decodeBytes(Uint8List b) => jsonDecode(utf8.decode(b));

class PerfLabScreen extends StatefulWidget {
  const PerfLabScreen({super.key});

  @override
  State<PerfLabScreen> createState() => _PerfLabScreenState();
}

class _PerfLabScreenState extends State<PerfLabScreen> {
  static final List<String> _results = []; // Giữ khi đóng/mở lại màn hình
  static int _total = 5000;
  static DemoScale _scale = DemoScale.medium;

  bool _isLandlord = false;
  Map<String, dynamic>? _stats;
  String? _statsError;
  String? _busy; // Mô tả việc đang chạy

  @override
  void initState() {
    super.initState();
    Security.getRole().then((r) {
      if (!mounted) return;
      setState(() => _isLandlord = (r ?? '').toUpperCase().contains('LANDLORD'));
      if (_isLandlord) _loadStats();
    });
  }

  // ============================ Dữ liệu demo ============================
  Future<void> _loadStats() async {
    try {
      final s = await DemoAPI.stats();
      if (mounted) setState(() {
        _stats = s;
        _statsError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _statsError = e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _run(String label, Future<void> Function() job) async {
    if (_busy != null) return;
    setState(() => _busy = label);
    try {
      await job();
    } catch (e) {
      _addResult('❌ $label: ${e.toString().replaceAll('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _addResult(String text) {
    final time = DateTime.now().toString().substring(11, 19);
    setState(() => _results.insert(0, '[$time] $text'));
  }

  Future<void> _seed() => _run('Sinh dữ liệu ${_scale.label}', () async {
        final r = await DemoAPI.seed(_scale);
        _addResult('✅ Sinh dữ liệu demo (${_scale.label}) trong ${r['elapsedMs']} ms\n'
            '${r['properties']} khu · ${r['rooms']} phòng · ${r['tenants']} người thuê · ${r['invoices']} hóa đơn\n'
            '${r['cards']} thẻ · ${r['accessLogs']} lượt quẹt · ${r['transactions']} giao dịch\n'
            'Đăng nhập người thuê demo: ${r['tenantLoginExample']} / ${r['tenantPassword']}');
        await _loadStats();
      });

  Future<void> _wipe() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa dữ liệu demo?'),
        content: const Text('Chỉ xóa khu trọ "[DEMO] ..." và người thuê @demo.qlpt của tài khoản này. Dữ liệu thật giữ nguyên.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xóa')),
        ],
      ),
    );
    if (ok != true) return;
    await _run('Xóa dữ liệu demo', () async {
      final r = await DemoAPI.wipe();
      _addResult('🗑 Đã xóa dữ liệu demo: $r');
      await _loadStats();
    });
  }

  // ============================ Bài đo ============================

  /// Đo parse JSON: UI thread vs compute(). "UI đứng" = khoảng lặng dài nhất của 1 timer 8ms chạy song song.
  Future<void> _benchJson() => _run('Đo parse JSON', () async {
        final bytes = await DemoAPI.rawFeed(_total);
        final main = await _measureBlocking(() async => _decodeBytes(bytes));
        final iso = await _measureBlocking(() => compute(_decodeBytes, bytes));
        _addResult('🧮 Parse JSON $_total phần tử (${(bytes.length / 1024).toStringAsFixed(0)} KB)\n'
            '• jsonDecode trên UI thread: ${main.$1} ms, UI đứng ${main.$2} ms (~${(main.$2 / 16.7).floor()} khung hình mất)\n'
            '• compute() / Isolate:       ${iso.$1} ms, UI đứng ${iso.$2} ms'
            '${kIsWeb ? '\n(Web không có isolate thật nên 2 cách giống nhau)' : ''}');
      });

  Future<(int, int)> _measureBlocking(Future<dynamic> Function() fn) async {
    var maxGap = 0;
    var last = DateTime.now();
    final timer = Timer.periodic(const Duration(milliseconds: 8), (_) {
      final now = DateTime.now();
      final gap = now.difference(last).inMilliseconds;
      if (gap > maxGap) maxGap = gap;
      last = now;
    });
    await Future.delayed(const Duration(milliseconds: 60));
    maxGap = 0;
    final sw = Stopwatch()..start();
    await fn();
    sw.stop();
    await Future.delayed(const Duration(milliseconds: 60));
    timer.cancel();
    return (sw.elapsedMilliseconds, maxGap);
  }

  /// Đo tải lại cùng 1 dữ liệu 2 lần: không ETag vs có ETag (304).
  Future<void> _benchEtag() => _run('Đo ETag', () async {
        final path = DemoAPI.feedPath(page: 0, size: 0, total: _total);
        final lines = <String>[];

        // A. Không tối ưu: GET thường 2 lần
        for (var i = 1; i <= 2; i++) {
          final headers = Map<String, String>.from(await ApiTotal.getAuthHeaders() as Map);
          final sw = Stopwatch()..start();
          final res = await http.get(Uri.parse('${ApiTotal.baseUrl}$path'), headers: headers);
          await compute(_decodeBytes, res.bodyBytes);
          sw.stop();
          lines.add('• Không ETag lần $i: HTTP ${res.statusCode}, ${(res.bodyBytes.length / 1024).toStringAsFixed(0)} KB, ${sw.elapsedMilliseconds} ms');
        }

        // B. Có ETag + DB phụ (ép bật tạm thời, không đổi cấu hình người dùng)
        final prev = PerfFlags.etagLocalDb.notifier.value;
        PerfFlags.etagLocalDb.notifier.value = true;
        try {
          for (var i = 1; i <= 2; i++) {
            final before304 = SyncedApi.stats.notModified;
            final beforeBytes = SyncedApi.stats.bytesDownloaded;
            final sw = Stopwatch()..start();
            await SyncedApi.getJson(path);
            sw.stop();
            final is304 = SyncedApi.stats.notModified > before304;
            final kb = (SyncedApi.stats.bytesDownloaded - beforeBytes) / 1024;
            lines.add('• Có ETag lần $i: HTTP ${is304 ? 304 : 200}, ${kb.toStringAsFixed(1)} KB, ${sw.elapsedMilliseconds} ms');
          }
        } finally {
          PerfFlags.etagLocalDb.notifier.value = prev;
        }
        _addResult('🌐 Tải lại danh sách $_total phần tử\n${lines.join('\n')}');
      });

  Future<void> _clearCaches() => _run('Xóa cache', () async {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        await AppCacheManager.instance.emptyCache();
        await SyncedApi.clear();
        SyncedApi.stats.reset();
        PerfCounters.itemBuilds = 0;
        _addResult('🧹 Đã xóa cache ảnh (RAM + đĩa), database phụ và bộ đếm -> đo lại từ đầu cho công bằng');
      });

  void _openFeed() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => DemoFeedScreen(total: _total)));
  }

  // ============================ Giao diện ============================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Hiệu năng & Demo · ${PerfFlags.buildLabel}', style: const TextStyle(fontSize: 16))),
      body: AnimatedBuilder(
        animation: PerfFlags.changes,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
          children: [
            if (_busy != null)
              Card(
                color: Colors.blue.shade50,
                child: ListTile(
                  leading: const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
                  title: Text('Đang chạy: $_busy...'),
                ),
              ),
            _section('1. Dữ liệu demo trên server', Icons.storage, _dataSection()),
            _section('2. Hiển thị số liệu', Icons.monitor_heart, _overlaySection()),
            _section('3. Bật / tắt kỹ thuật tối ưu', Icons.tune, _flagsSection()),
            _section('4. Bài đo', Icons.speed, _benchSection()),
            _section('5. Kết quả đo', Icons.assignment, _resultsSection()),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, IconData icon, Widget child) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: Colors.blueAccent),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ]),
            const SizedBox(height: 8),
            child,
          ]),
        ),
      );

  Widget _dataSection() {
    if (!_isLandlord) {
      return const Text('Đăng nhập tài khoản CHỦ TRỌ để sinh dữ liệu demo. '
          'Người thuê vẫn dùng được bảng FPS/RAM và công tắc tối ưu.');
    }
    final s = _stats;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_statsError != null) Text(_statsError!, style: const TextStyle(color: Colors.red)),
      if (s != null)
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in {
            'Khu trọ': s['properties'],
            'Phòng': s['rooms'],
            'Người thuê': s['tenants'],
            'Hóa đơn': s['invoices'],
            'Thẻ': s['cards'],
            'Lượt quẹt': s['accessLogs'],
            'Giao dịch': s['transactions'],
          }.entries)
            Chip(label: Text('${e.key}: ${e.value}'), visualDensity: VisualDensity.compact),
        ]),
      const SizedBox(height: 8),
      SegmentedButton<DemoScale>(
        segments: [
          for (final sc in DemoScale.values)
            ButtonSegment(value: sc, label: Text('${sc.label}\n${sc.rooms} phòng', textAlign: TextAlign.center)),
        ],
        selected: {_scale},
        onSelectionChanged: (v) => setState(() => _scale = v.first),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _busy == null ? _seed : null,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Sinh dữ liệu'),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _busy == null ? _wipe : null,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Xóa demo'),
        ),
      ]),
      const SizedBox(height: 4),
      Text('Sinh lại sẽ thay thế bộ demo cũ. Mật khẩu người thuê demo: 123456.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
    ]);
  }

  Widget _overlaySection() => Column(children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(PerfFlags.showOverlay.title),
          subtitle: const Text('FPS, thời gian khung hình, jank, RAM, ảnh trong RAM, số lần build, mạng. '
              'Kéo để di chuyển, chạm để thu gọn, ● REC để ghi.'),
          value: PerfFlags.showOverlay.value,
          onChanged: (v) => PerfFlags.set(PerfFlags.showOverlay, v),
        ),
        Text('Số liệu chuẩn nhất khi chạy: flutter run --profile (trên điện thoại thật).',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ]);

  Widget _flagsSection() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: () => PerfFlags.setAllOptimizations(true),
              icon: const Icon(Icons.rocket_launch),
              label: const Text('Bật hết tối ưu'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.deepOrange),
              onPressed: () => PerfFlags.setAllOptimizations(false),
              icon: const Icon(Icons.warning_amber),
              label: const Text('Tắt hết tối ưu'),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Center(
          child: Text('Chế độ hiện tại: ${PerfFlags.modeLabel}',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: PerfFlags.allOptimized ? Colors.green : Colors.deepOrange)),
        ),
        for (final f in PerfFlags.optimizations)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(f.title),
            subtitle: Text(f.value ? '✅ ${f.onText}' : '⚠️ ${f.offText}',
                style: TextStyle(color: f.value ? Colors.green.shade700 : Colors.deepOrange)),
            value: f.value,
            onChanged: (v) => PerfFlags.set(f, v),
          ),
        Text('Mở lại màn hình danh sách sau khi đổi công tắc để áp dụng.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ]);

  Widget _benchSection() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Số phần tử danh sách ảo:'),
        const SizedBox(height: 4),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 1000, label: Text('1.000')),
            ButtonSegment(value: 5000, label: Text('5.000')),
            ButtonSegment(value: 20000, label: Text('20.000')),
          ],
          selected: {_total},
          onSelectionChanged: (v) => setState(() => _total = v.first),
        ),
        if (!PerfFlags.listBuilder.value && _total > 1000)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('⚠️ Đang tắt ListView.builder: build cùng lúc nhiều dòng + ảnh lớn có thể làm app rất chậm/văng.',
                style: TextStyle(color: Colors.deepOrange, fontSize: 12)),
          ),
        const SizedBox(height: 8),
        _benchButton(Icons.insights, 'SO SÁNH TRÊN APP THẬT (dữ liệu thật) + biểu đồ',
            'Đo tự động hoặc thủ công trên các màn Nhà trọ / Dịch vụ / Người dùng / Thẻ, cả 2 chế độ, vẽ biểu đồ so sánh',
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RealCompareScreen()))),
        _benchButton(Icons.science, 'Bộ test từng kỹ thuật T1–T8 (bài đo riêng lẻ)',
            'Đo tách riêng từng kỹ thuật trong điều kiện kiểm soát; T3 kiểm tra luật lưu ảnh 3 tháng / đổi chủ',
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TestSuiteScreen()))),
        _benchButton(Icons.view_list, 'Mở danh sách demo có ảnh',
            'Bấm "Tự cuộn & đo 15s" trong màn hình để ra số liệu FPS/RAM', _isLandlord ? _openFeed : null),
        _benchButton(Icons.photo_library, 'Ảnh công tơ (1.000 ảnh) + Tự so sánh',
            'Lưới ảnh – thấy rõ nhất tác dụng tối ưu ảnh. Nút "Tự so sánh" tự đo 2 chế độ', _isLandlord
                ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MeterGalleryScreen()))
                : null),
        _benchButton(Icons.data_object, 'Đo parse JSON: UI thread vs compute()',
            'Đo thời gian và số ms giao diện bị đứng', _isLandlord && _busy == null ? _benchJson : null),
        _benchButton(Icons.sync, 'Đo tải lại dữ liệu: có / không ETag',
            'So sánh dung lượng tải + thời gian khi dữ liệu không đổi', _isLandlord && _busy == null ? _benchEtag : null),
        _benchButton(Icons.cleaning_services, 'Xóa cache ảnh + database phụ',
            'Làm trước mỗi lần đo để so sánh công bằng', _busy == null ? _clearCaches : null),
      ]);

  Widget _benchButton(IconData icon, String title, String sub, VoidCallback? onTap) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: onTap == null ? Colors.grey : Colors.blueAccent),
        title: Text(title),
        subtitle: Text(sub),
        trailing: const Icon(Icons.chevron_right),
        enabled: onTap != null,
        onTap: onTap,
      );

  Widget _resultsSection() {
    final reports = PerfMonitor.instance.reports;
    if (_results.isEmpty && reports.isEmpty) {
      return const Text('Chưa có kết quả. Chạy 1 bài đo hoặc bấm ● REC trên bảng FPS.');
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        TextButton.icon(
          icon: const Icon(Icons.copy),
          label: const Text('Copy tất cả'),
          onPressed: () {
            final text = [
              ...reports.map((r) => r.summary()),
              ..._results,
            ].join('\n\n');
            Clipboard.setData(ClipboardData(text: text));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã copy, dán vào báo cáo')));
          },
        ),
        TextButton.icon(
          icon: const Icon(Icons.delete_sweep),
          label: const Text('Xóa'),
          onPressed: () => setState(() {
            _results.clear();
            reports.clear();
          }),
        ),
      ]),
      for (final r in reports)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.insights, color: r.mode == 'ĐÃ TỐI ƯU' ? Colors.green : Colors.deepOrange),
          title: Text('${r.label} – ${r.mode}'),
          subtitle: Text('FPS TB ${r.avgFps.toStringAsFixed(1)} · jank ${r.jankPercent.toStringAsFixed(1)}% · '
              'RAM max ${r.maxRss.toStringAsFixed(0)} MB · ảnh ${r.maxImageMb.toStringAsFixed(0)} MB'),
          onTap: () => showPerfReportDialog(context, r),
        ),
      for (final t in _results)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
          child: SelectableText(t, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ),
    ]);
  }
}
