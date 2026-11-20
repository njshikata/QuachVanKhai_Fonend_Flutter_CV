// ĐO TỰ ĐỘNG TRÊN APP THẬT – DỮ LIỆU THẬT
// Mở đúng ứng dụng (MyApp, có bảng FPS/RAM), đăng nhập tài khoản chủ trọ, vào "So sánh trên app thật",
// chạy đo tự động mọi màn hình ở 2 chế độ, rồi in bảng Markdown ra console ([REAL]).
// Kết quả cũng được lưu trong app: mở lại màn "So sánh trên app thật" để xem biểu đồ.
//   flutter drive --profile -d <máy> --driver=test_driver/integration_test.dart --target=integration_test/real_app_test.dart \
//     --dart-define=API_HOST=<ip backend> --dart-define=TEST_EMAIL=<email chủ trọ> --dart-define=TEST_PASS=<mật khẩu>
// Tùy chọn: --dart-define=REAL_SECONDS=15 (giây cuộn mỗi lượt), --dart-define=REAL_ONLY=service,cards

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:qlpt_frontend/Source/api/Login/LoginAPI.dart';
import 'package:qlpt_frontend/Source/perf/PerfFlags.dart';
import 'package:qlpt_frontend/Source/perf/PerfMonitor.dart';
import 'package:qlpt_frontend/Source/perf/real/RealBench.dart';
import 'package:qlpt_frontend/Source/perf/real/RealCompareScreen.dart';
import 'package:qlpt_frontend/main.dart';

const _email = String.fromEnvironment('TEST_EMAIL');
const _pass = String.fromEnvironment('TEST_PASS');
const _seconds = int.fromEnvironment('REAL_SECONDS', defaultValue: 10);
const _only = String.fromEnvironment('REAL_ONLY');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('So sánh trên app thật', (tester) async {
    await PerfFlags.load();
    await RealBench.init();
    expect(await LoginAPI.login(_email, _pass), 'SUCCESS');

    await tester.pumpWidget(const MyApp()); // Chính ứng dụng thật
    await tester.pump(const Duration(seconds: 1));
    final key = GlobalKey<RealCompareScreenState>();
    PerfMonitor.navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => RealCompareScreen(key: key)));
    await tester.pump(const Duration(seconds: 2));

    final screens = realScreens.where((s) => _only.isEmpty || _only.split(',').contains(s.id)).toList();
    var done = false;
    key.currentState!.runAuto(screens: screens, seconds: _seconds).whenComplete(() => done = true);
    final sw = Stopwatch()..start();
    while (!done) {
      if (sw.elapsed.inMinutes >= 25) fail('Đo quá 25 phút');
      await tester.pump(const Duration(milliseconds: 200));
    }
    for (final line in RealBench.markdown().split('\n')) {
      debugPrint('[REAL] $line');
    }
    // Giữ màn kết quả (biểu đồ) 20 giây để xem / chụp màn hình
    await tester.pump(const Duration(seconds: 20));
  }, timeout: const Timeout(Duration(minutes: 30)));
}
