// Đường dẫn: integration_test/perf_test.dart
//
// BÀI ĐO HIỆU NĂNG TỰ ĐỘNG (chạy app thật, bản PROFILE, gọi backend thật).
// Với mỗi màn hình danh sách lớn: đo thời gian tải dữ liệu + tự cuộn và ghi lại từng khung hình
// (thời gian build UI thread, raster GPU thread, % khung hình giật). Chạy 2 lần: TẮT hết tối ưu và BẬT hết tối ưu.
//
// Cách dễ nhất: run_frontend.bat -> chọn 3. "ĐO HIỆU NĂNG TỰ ĐỘNG".
// Chạy trên máy ảo / điện thoại Android (backend phải đang chạy, tài khoản CHỦ TRỌ đã sinh dữ liệu demo):
//   flutter drive --profile -d emulator-5554 --driver=test_driver/integration_test.dart ^
//     --target=integration_test/perf_test.dart ^
//     --dart-define=TEST_EMAIL=<email> --dart-define=TEST_PASS=<mật khẩu>
// Kết quả in ra console (dòng bắt đầu bằng [PERF] và bảng KẾT QUẢ ĐO)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:qlpt_frontend/Source/api/Login/LoginAPI.dart';
import 'package:qlpt_frontend/Source/api/SyncedApi.dart';
import 'package:qlpt_frontend/Source/perf/DemoFeedScreen.dart';
import 'package:qlpt_frontend/Source/perf/PerfFlags.dart';
import 'package:qlpt_frontend/Source/scr/HomePage/landlady/ServiceRoom/ServiceRoomScreen.dart';
import 'package:qlpt_frontend/Source/scr/HomePage/landlady/Tab/TabUser/Manage_User_Screen.dart';
import 'package:qlpt_frontend/Source/scr/HomePage/landlady/Tab/room/Dashboard_Properti_Screen.dart';

const _email = String.fromEnvironment('TEST_EMAIL');
const _pass = String.fromEnvironment('TEST_PASS');
const _scrollSeconds = 6;
// Chỉ đo một số màn (vd --dart-define=PERF_ONLY=service,demo); để trống = đo tất cả
const _only = String.fromEnvironment('PERF_ONLY');

class _Result {
  final String screen;
  final String mode;
  final int loadMs;
  final List<FrameTiming> frames;
  final Duration scrollTime;
  final String? error;

  _Result(this.screen, this.mode, this.loadMs, this.frames, this.scrollTime, {this.error});

  double _avg(Iterable<double> v) => v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;
  double _pct(List<double> v, double p) {
    if (v.isEmpty) return 0;
    final s = [...v]..sort();
    return s[((s.length - 1) * p).round()];
  }

  List<double> get _build => frames.map((f) => f.buildDuration.inMicroseconds / 1000).toList();
  List<double> get _raster => frames.map((f) => f.rasterDuration.inMicroseconds / 1000).toList();
  List<double> get _worst => [for (final f in frames) (f.buildDuration > f.rasterDuration ? f.buildDuration : f.rasterDuration).inMicroseconds / 1000];
  int get jank => _worst.where((ms) => ms > 16.7).length;
  double get fps => scrollTime.inMilliseconds == 0 ? 0 : frames.length * 1000 / scrollTime.inMilliseconds;

  String pretty() => error != null
      ? '$screen [$mode]\nLỖI: $error'
      : '$screen [$mode]\n'
          'Tải dữ liệu: $loadMs ms | FPS khi cuộn: ${fps.toStringAsFixed(0)}\n'
          'Build TB: ${_avg(_build).toStringAsFixed(2)} ms | Raster TB: ${_avg(_raster).toStringAsFixed(2)} ms\n'
          'P90 / chậm nhất: ${_pct(_worst, 0.9).toStringAsFixed(1)} / ${_pct(_worst, 1).toStringAsFixed(1)} ms | '
          'Khung giật: $jank/${frames.length}';

  String row() => error != null
      ? '| $screen | $mode | LỖI: $error | | | | | |'
      : '| $screen | $mode | $loadMs ms | ${fps.toStringAsFixed(0)} | ${_avg(_build).toStringAsFixed(2)} | '
          '${_avg(_raster).toStringAsFixed(2)} | ${_pct(_worst, 0.9).toStringAsFixed(1)} / ${_pct(_worst, 1).toStringAsFixed(1)} | '
          '$jank/${frames.length} (${frames.isEmpty ? 0 : (jank * 100 / frames.length).toStringAsFixed(1)}%) |';
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final results = <_Result>[];

  Future<void> waitFor(WidgetTester tester, Finder f, {Duration timeout = const Duration(minutes: 3)}) async {
    final sw = Stopwatch()..start();
    while (f.evaluate().isEmpty) {
      if (sw.elapsed > timeout) throw Exception('Hết thời gian chờ ${timeout.inSeconds}s');
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Scrollable dọc có nội dung dài nhất trên màn hình (danh sách chính).
  ScrollPosition mainScroll(WidgetTester tester) {
    ScrollPosition? best;
    for (final e in find.byType(Scrollable).evaluate()) {
      final st = (e as StatefulElement).state as ScrollableState;
      final pos = st.position;
      if (pos.axis != Axis.vertical || !pos.hasContentDimensions) continue;
      if (best == null || pos.maxScrollExtent > best.maxScrollExtent) best = pos;
    }
    return best!;
  }

  Future<void> measure(WidgetTester tester, String name, Widget screen, Finder ready) async {
    final mode = PerfFlags.allOptimized ? 'TỐI ƯU' : 'KHÔNG tối ưu';
    await SyncedApi.clear(); // Không dùng cache RAM của lần đo trước -> so sánh công bằng
    PaintingBinding.instance.imageCache.clear();
    final load = Stopwatch()..start();
    await tester.pumpWidget(MaterialApp(home: screen));
    try {
      await waitFor(tester, ready);
      load.stop();
      await tester.pump(const Duration(milliseconds: 500));

      final frames = <FrameTiming>[];
      void cb(List<FrameTiming> t) => frames.addAll(t);
      SchedulerBinding.instance.addTimingsCallback(cb);
      final pos = mainScroll(tester);
      final sw = Stopwatch()..start();
      // Cuộn đều ~2400 px/giây xuống, hết danh sách thì nhảy lên đầu (giống người dùng vuốt liên tục)
      while (sw.elapsed.inSeconds < _scrollSeconds) {
        final target = pos.pixels + 1200;
        if (target >= pos.maxScrollExtent) {
          await pos.animateTo(pos.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.linear);
          pos.jumpTo(0);
          await tester.pump(const Duration(milliseconds: 16));
          continue;
        }
        await pos.animateTo(target, duration: const Duration(milliseconds: 500), curve: Curves.linear);
      }
      sw.stop();
      await tester.pump(const Duration(milliseconds: 300)); // Nhận nốt FrameTiming còn lại
      SchedulerBinding.instance.removeTimingsCallback(cb);
      results.add(_Result(name, mode, load.elapsedMilliseconds, frames, sw.elapsed));
    } catch (e) {
      results.add(_Result(name, mode, load.elapsedMilliseconds, const [], Duration.zero, error: e.toString()));
    }
    debugPrint('[PERF] ${results.last.row()}');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('Đo hiệu năng các màn danh sách lớn', (tester) async {
    expect(_email.isNotEmpty && _pass.isNotEmpty, true, reason: 'Thiếu --dart-define=TEST_EMAIL / TEST_PASS');
    await PerfFlags.load();
    final login = await LoginAPI.login(_email, _pass);
    expect(login, 'SUCCESS', reason: 'Đăng nhập thất bại: $login');

    // Lỗi tải ảnh (vd bản KHÔNG tối ưu bắn hàng nghìn request ảnh gốc làm nghẽn mạng) chỉ đếm lại,
    // không làm hỏng cả bài đo. Các lỗi khác vẫn báo bình thường.
    final origOnError = FlutterError.onError;
    var imageErrors = 0;
    FlutterError.onError = (details) {
      if (details.library == 'image resource service') {
        imageErrors++;
        return;
      }
      origOnError?.call(details);
    };

    // Đo bản TỐI ƯU trước: bản không tối ưu làm nghẽn mạng/RAM, đo sau để không ảnh hưởng số liệu bản tối ưu
    for (final optimized in [true, false]) {
      await PerfFlags.setAllOptimizations(optimized);
      if (_only.isEmpty || _only.contains('dashboard')) {
        await measure(tester, 'Dashboard phòng', const DashboardPropertiScreen(), find.textContaining('Tổng:'));
      }
      if (_only.isEmpty || _only.contains('service')) {
        await measure(tester, 'Dịch vụ phòng', const ServiceRoomScreen(), find.textContaining('Phòng '));
      }
      if (_only.isEmpty || _only.contains('users')) {
        await measure(tester, 'Khách thuê', const ManageUserScreen(), find.byIcon(Icons.chevron_right));
      }
      if (_only.isEmpty || _only.contains('demo')) {
        await measure(tester, 'Demo 5000 dòng', const DemoFeedScreen(total: 5000), find.textContaining('#1 '));
      }
    }
    await PerfFlags.setAllOptimizations(true);
    FlutterError.onError = origOnError;
    debugPrint('[PERF] Số ảnh tải lỗi (timeout/nghẽn mạng): $imageErrors');

    final table = StringBuffer()
      ..writeln('| Màn hình | Chế độ | Tải dữ liệu | FPS khi cuộn | Build TB (ms) | Raster TB (ms) | P90 / chậm nhất (ms) | Khung giật >16.7ms |')
      ..writeln('|---|---|---|---|---|---|---|---|');
    for (final r in results) {
      table.writeln(r.row());
    }
    // ignore: avoid_print
    print('\n===== KẾT QUẢ ĐO =====\n$table');

    // Hiện bảng kết quả trên máy ảo 15s (hoặc tới khi bấm "Xong"); bảng đầy đủ đã in ra console
    final done = Completer<void>();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('KẾT QUẢ ĐO HIỆU NĂNG')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final r in results)
              Card(
                color: r.mode == 'TỐI ƯU' ? Colors.green.shade50 : Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: SelectableText(r.pretty(), style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton(onPressed: () => done.complete(), child: const Text('Xong')),
          ]),
        ),
      ),
    ));
    await done.future.timeout(const Duration(seconds: 15), onTimeout: () {});
  }, timeout: const Timeout(Duration(minutes: 60)));
}
