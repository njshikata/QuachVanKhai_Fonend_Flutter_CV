// Đường dẫn: lib/Source/perf/real/RestartBench.dart
//
// ============================================================================================
//  BÀI ĐO TRỰC QUAN NHẤT: TẮT HẲN APP RỒI BẬT LẠI
// ============================================================================================
//
// Mô phỏng đúng việc người dùng vuốt tắt app rồi bấm icon mở lại:
//   1. Bấm nút: app lưu "kế hoạch đo" (màn nào, chế độ nào, thời điểm bấm) vào SharedPreferences.
//   2. App TỰ TẮT HẲN: process bị kill (MainActivity.kt -> RestartActivity.kt), mọi RAM / cache trong bộ nhớ mất hết.
//   3. Android mở lại app từ đầu. Người xem thấy app biến mất rồi hiện lại.
//   4. main() đọc kế hoạch, bật/tắt các kỹ thuật tối ưu theo chế độ, app tự vào màn cần đo
//      (dùng token đăng nhập đã lưu), ghi:
//        - Bật lại app tới khung hình đầu (ms)
//        - Từ lúc bấm tới khi THẤY DỮ LIỆU trên màn hình (ms)  <- con số trực quan nhất
//        - FPS / khung hình đứng / RAM khi tự cuộn
//   5. Lưu kết quả, rồi tự tắt/bật cho lượt kế tiếp. Hết kế hoạch thì mở màn biểu đồ so sánh.
//
// Những gì CÒN sau khi tắt app (giống người dùng thật): ảnh trên đĩa (cache 3 tháng) và database phụ SQLite
// (ETag). Đó chính là lợi ích của bản tối ưu khi mở lại app. Bản chưa tối ưu không dùng các bộ nhớ này.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qlpt_frontend/Source/api/SyncedApi.dart';
import 'package:qlpt_frontend/Source/scr/HomePage/landlady/landladyScreen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../PerfFlags.dart';
import '../PerfMonitor.dart';
import 'RealBench.dart';
import 'RealCompareScreen.dart';

class RestartBench {
  static const _planKey = 'real_bench_restart_plan_v1';
  static const _channel = MethodChannel('qlpt/app');

  /// Khoảng chờ cố định sau khi kill app cũ (RestartActivity.SETTLE_MS) -> trừ ra khỏi số đo.
  static const _settleMs = 1500;

  /// Kế hoạch đang chạy (null = không có). Đọc trong prepareBoot().
  static Map<String, dynamic>? _plan;

  /// true khi lần mở app này là do bài đo khởi động lại.
  static bool get active => _plan != null;

  // ------------------------------------------------------------------------------------------
  // BẮT ĐẦU
  // ------------------------------------------------------------------------------------------

  /// Đo tự động: mỗi màn 2 lượt tắt/bật app (CHƯA và ĐÃ tối ưu, thứ tự đảo luân phiên giữa các màn).
  /// Trước đó mở mỗi màn 1 lần ở bản tối ưu (không tính điểm) để máy có dữ liệu cục bộ như người dùng thật đã dùng app.
  static Future<void> startAuto(NavigatorState nav, List<RealScreen> screens, {int scrollSeconds = 8}) async {
    await RealBench.clear(); // lượt đo mới: ẩn toàn bộ kết quả cũ, chỉ hiện kết quả của lượt này
    final saved = {for (final f in PerfFlags.optimizations) f: f.value};
    try {
      for (final f in PerfFlags.optimizations) {
        f.notifier.value = true;
      }
      for (final s in screens) {
        RealBench.status.value = 'Chuẩn bị: mở "${s.name}" 1 lần (không tính điểm)...';
        final key = GlobalKey();
        final route = MaterialPageRoute<void>(builder: (_) => KeyedSubtree(key: key, child: s.build()));
        unawaited(nav.push(route));
        try {
          await RealBench.waitForContent(key, timeout: const Duration(seconds: 120));
          await Future<void>.delayed(const Duration(milliseconds: 1500)); // đợi lưu SQLite xong
        } catch (_) {
        } finally {
          if (route.isActive) nav.removeRoute(route);
        }
      }
    } finally {
      for (final e in saved.entries) {
        e.key.notifier.value = e.value;
      }
    }
    // Đảo thứ tự luân phiên (màn 1: CHƯA rồi ĐÃ, màn 2: ĐÃ rồi CHƯA...) để không chế độ nào luôn bị đo
    // ngay sau một lượt nặng -> so sánh công bằng.
    await _startPlan([
      for (var i = 0; i < screens.length; i++)
        for (final optimized in i.isEven ? const [false, true] : const [true, false])
          {'screen': screens[i].id, 'optimized': optimized},
    ], scrollSeconds);
  }

  /// Đo thủ công 1 lượt: tắt/bật app rồi mở [screen] ở chế độ [optimized].
  static Future<void> startOne(RealScreen screen, bool optimized, {int scrollSeconds = 8}) =>
      _startPlan([{'screen': screen.id, 'optimized': optimized}], scrollSeconds);

  static Future<void> _startPlan(List<Map<String, dynamic>> steps, int scrollSeconds) async {
    _plan = {'steps': steps, 'index': 0, 'scroll': scrollSeconds};
    await _restartNow();
  }

  static Future<void> cancel() async {
    _plan = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_planKey);
    RealBench.status.value = null;
  }

  /// Lưu kế hoạch + thời điểm bấm rồi tắt hẳn app (Android sẽ mở lại).
  static Future<void> _restartNow() async {
    final plan = _plan!;
    final steps = plan['steps'] as List;
    final step = steps[plan['index'] as int] as Map;
    final screen = _screen(step['screen'] as String);
    final mode = step['optimized'] == true ? BenchMode.after : BenchMode.before;
    for (var i = 3; i > 0; i--) {
      RealBench.status.value =
          'Lượt ${plan['index'] + 1}/${steps.length}: ${screen.name} – ${mode.label}\nTẮT APP sau $i giây, app sẽ tự bật lại...';
      await Future<void>.delayed(const Duration(seconds: 1));
      if (_plan == null) return; // đã hủy
    }
    plan['tapAt'] = DateTime.now().millisecondsSinceEpoch;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_planKey, jsonEncode(plan));
    try {
      await _channel.invokeMethod('restart');
    } on MissingPluginException {
      RealBench.status.value = 'Thiết bị này không hỗ trợ tự khởi động lại (chỉ có trên Android).';
      await cancel();
    }
  }

  static RealScreen _screen(String id) => realScreens.firstWhere((s) => s.id == id, orElse: () => realScreens.first);

  // ------------------------------------------------------------------------------------------
  // SAU KHI APP BẬT LẠI
  // ------------------------------------------------------------------------------------------

  /// Gọi trong main() SAU PerfFlags.load(), TRƯỚC runApp(): bật/tắt kỹ thuật theo lượt đo.
  /// Chỉ đổi tạm (notifier), không ghi đè cài đặt đã lưu của người dùng.
  static Future<void> prepareBoot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_planKey);
      if (raw == null) return;
      final plan = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final steps = plan['steps'] as List;
      if ((plan['index'] as int) >= steps.length || plan['tapAt'] == null) {
        await prefs.remove(_planKey);
        return;
      }
      // Kế hoạch quá cũ (vd app bị tắt giữa chừng hôm trước) -> bỏ
      if (DateTime.now().millisecondsSinceEpoch - (plan['tapAt'] as int) > 120000) {
        await prefs.remove(_planKey);
        return;
      }
      _plan = plan;
      final optimized = (steps[plan['index'] as int] as Map)['optimized'] == true;
      for (final f in PerfFlags.optimizations) {
        f.notifier.value = optimized;
      }
      PerfFlags.showOverlay.notifier.value = true; // hiện bảng FPS/RAM cho người xem
    } catch (_) {}
  }

  /// Gọi ngay sau runApp(): đợi khung hình đầu, mở màn cần đo, đo và lưu, rồi chuyển lượt kế.
  static Future<void> resumeAfterBoot() async {
    final plan = _plan;
    if (plan == null) return;
    await WidgetsBinding.instance.endOfFrame; // khung hình đầu tiên đã vẽ
    final tapAt = (plan['tapAt'] as int) + _settleMs; // bỏ khoảng chờ cố định khi khởi động lại
    final bootMs = DateTime.now().millisecondsSinceEpoch - tapAt;

    final steps = plan['steps'] as List;
    final index = plan['index'] as int;
    final step = steps[index] as Map;
    final screen = _screen(step['screen'] as String);
    final mode = step['optimized'] == true ? BenchMode.after : BenchMode.before;
    final scrollSeconds = plan['scroll'] as int? ?? 8;
    final title = 'Lượt ${index + 1}/${steps.length}: ${screen.name} – ${mode.label}';

    NavigatorState? nav;
    while ((nav = PerfMonitor.navigatorKey.currentState) == null) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    SyncedApi.stats.reset();
    PerfCounters.itemBuilds = 0;
    RealBench.externalRecording = true; // kết quả lưu ở dưới, không để bộ ghi thủ công lưu thêm bản "Ghi tự do"
    PerfMonitor.instance.startRecording('${screen.name} [${mode.label}] tắt/bật app');
    RealBench.status.value = '$title\nApp đã bật lại sau $bootMs ms, đang tải dữ liệu...';
    final key = GlobalKey();
    final route = MaterialPageRoute<void>(builder: (_) => KeyedSubtree(key: key, child: screen.build()));
    unawaited(nav!.push(route));
    int? openMs;
    try {
      final pos = await RealBench.waitForContent(key, timeout: const Duration(seconds: 150));
      openMs = DateTime.now().millisecondsSinceEpoch - tapAt;
      RealBench.status.value = '$title\nTHẤY DỮ LIỆU sau $openMs ms (tính từ lúc tắt app). Đang tự cuộn ${scrollSeconds}s...';
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await RealBench.autoScroll(pos, Duration(seconds: scrollSeconds));
      await Future<void>.delayed(const Duration(milliseconds: 1100));
    } catch (e) {
      RealBench.status.value = '$title\nLỗi: $e';
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    final report = PerfMonitor.instance.stopRecording();
    RealBench.externalRecording = false;
    if (report != null && openMs != null) {
      await RealBench.add(BenchRun.fromReport(report,
          screen: '${screen.name} · tắt/bật app', auto: true, openMs: openMs, bootMs: bootMs, mode: mode, totals: true),
          session: steps.length > 1);
    }

    if (_plan == null) return; // người dùng bấm Hủy trong lúc đo
    plan['index'] = index + 1;
    if (index + 1 < steps.length) {
      await _restartNow();
      return;
    }
    // Hết kế hoạch: trả công tắc về cài đặt đã lưu, mở màn chính + màn biểu đồ
    await cancel();
    await PerfFlags.restoreSaved(); // tắt bảng FPS, trả công tắc về như trước khi đo
    for (final line in RealBench.markdown().split('\n')) {
      debugPrint('[REAL] $line'); // xem bằng: adb logcat | findstr REAL
    }
    nav.pushAndRemoveUntil(MaterialPageRoute<void>(builder: (_) => const LandladyScreen()), (_) => false);
    unawaited(nav.push(MaterialPageRoute<void>(builder: (_) => const RealCompareScreen())));
  }
}

/// Dải thông báo trên cùng màn hình khi đang đo (tự động / tắt-bật app), có nút Hủy.
class BenchBanner extends StatelessWidget {
  final Widget child;

  const BenchBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      child,
      ValueListenableBuilder<String?>(
        valueListenable: RealBench.status,
        builder: (context, s, _) {
          if (s == null) return const SizedBox.shrink();
          return Positioned(
            left: 8,
            right: 8,
            bottom: 24,
            child: Material(
              color: Colors.black.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                child: Row(children: [
                  const Icon(Icons.speed, color: Colors.amber, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(s, style: const TextStyle(color: Colors.white, fontSize: 12.5))),
                  TextButton(
                    onPressed: () {
                      RealBench.cancel();
                      RestartBench.cancel();
                    },
                    child: const Text('Hủy', style: TextStyle(color: Colors.amber)),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    ]);
  }
}
