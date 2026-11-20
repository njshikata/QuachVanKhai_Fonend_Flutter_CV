// TEST TỔNG THỂ TỰ ĐỘNG: đăng nhập -> mở "Bộ test tối ưu" -> chạy T1..T8 -> in bảng Markdown ra console ([SUITE]).
//   flutter drive --profile -d <máy> --driver=test_driver/integration_test.dart --target=integration_test/suite_test.dart \
//     --dart-define=API_HOST=<ip máy chạy backend> --dart-define=TEST_EMAIL=<email chủ trọ> --dart-define=TEST_PASS=<mật khẩu>
// Chạy 1 bài riêng: thêm --dart-define=SUITE_ONLY=T4

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:qlpt_frontend/Source/api/Login/LoginAPI.dart';
import 'package:qlpt_frontend/Source/perf/PerfFlags.dart';
import 'package:qlpt_frontend/Source/perf/suite/OptimizationTests.dart';
import 'package:qlpt_frontend/Source/perf/suite/TestSuiteScreen.dart';

const _email = String.fromEnvironment('TEST_EMAIL');
const _pass = String.fromEnvironment('TEST_PASS');
const _only = String.fromEnvironment('SUITE_ONLY');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('Bộ test tối ưu – tổng thể', (tester) async {
    await PerfFlags.load();
    expect(await LoginAPI.login(_email, _pass), 'SUCCESS');

    final key = GlobalKey<TestSuiteScreenState>();
    await tester.pumpWidget(MaterialApp(home: TestSuiteScreen(key: key)));
    await tester.pump(const Duration(milliseconds: 500));

    final s = key.currentState!;
    final Future<void> run = _only.isEmpty
        ? s.runAll()
        : s.runTest(allOptimizationTests.firstWhere((t) => t.id == _only));
    var done = false;
    run.whenComplete(() => done = true);
    final sw = Stopwatch()..start();
    while (!done) {
      if (sw.elapsed.inMinutes >= 15) fail('Bộ test chạy quá 15 phút');
      await tester.pump(const Duration(milliseconds: 200));
    }
    for (final line in s.markdown().split('\n')) {
      debugPrint('[SUITE] $line');
    }
    // Đóng hộp thoại tổng hợp (nếu có)
    await tester.pump(const Duration(seconds: 1));
  }, timeout: const Timeout(Duration(minutes: 20)));
}
