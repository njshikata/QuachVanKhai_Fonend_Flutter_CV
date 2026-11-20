// Kiểm tra màn "Ảnh công tơ": bấm "Tự so sánh", đợi bảng kết quả, in ra console.
//   flutter drive --profile -d emulator-5554 --driver=test_driver/integration_test.dart ^
//     --target=integration_test/meter_test.dart --dart-define=TEST_EMAIL=<email> --dart-define=TEST_PASS=<mật khẩu>

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:qlpt_frontend/Source/api/Login/LoginAPI.dart';
import 'package:qlpt_frontend/Source/perf/MeterGalleryScreen.dart';
import 'package:qlpt_frontend/Source/perf/PerfFlags.dart';

const _email = String.fromEnvironment('TEST_EMAIL');
const _pass = String.fromEnvironment('TEST_PASS');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('Ảnh công tơ – tự so sánh', (tester) async {
    await PerfFlags.load();
    expect(await LoginAPI.login(_email, _pass), 'SUCCESS');
    await PerfFlags.setAllOptimizations(true);

    await tester.pumpWidget(const MaterialApp(home: MeterGalleryScreen()));
    final sw = Stopwatch()..start();
    while (find.text('Tự so sánh').evaluate().isEmpty && sw.elapsed.inSeconds < 30) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Tự so sánh'));
    sw.reset();
    while (find.text('So sánh: ảnh công tơ').evaluate().isEmpty) {
      if (sw.elapsed.inMinutes >= 5) fail('Không ra bảng so sánh sau 5 phút');
      await tester.pump(const Duration(milliseconds: 200));
    }
    final table = find.byType(Table).evaluate().single.widget as Table;
    for (final r in table.children) {
      final cells = r.children.map((c) => ((c as Padding).child as Text).data).join(' | ');
      debugPrint('[METER] | $cells |');
    }
    debugPrint('[METER] flags sau khi so sánh: ${PerfFlags.modeLabel}');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
