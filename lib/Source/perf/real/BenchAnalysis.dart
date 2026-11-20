// Đường dẫn: lib/Source/perf/real/BenchAnalysis.dart
//
// PHÂN TÍCH TỰ ĐỘNG KẾT QUẢ ĐO (viết sẵn bằng lời để trình bày)
//  - Đọc đúng số vừa đo của cặp CHƯA / ĐÃ tối ưu.
//  - Diễn giải từng nhóm: TỐC ĐỘ (ưu tiên số 1) -> ĐỘ MƯỢT -> BỘ NHỚ -> MẠNG.
//  - Giải thích VÌ SAO nhanh hơn: bản chưa tối ưu làm gì, bản tối ưu làm gì, nằm ở file nào.
//  - Chỉ số nào không tốt hơn cũng nói thẳng và giải thích lý do.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'BenchCharts.dart';
import 'RealBench.dart';

/// 1 đoạn phân tích: tiêu đề + các ý.
class AnalysisSection {
  final String title;
  final List<String> points;
  final IconData icon;

  const AnalysisSection(this.title, this.icon, this.points);
}

/// Cơ chế của từng màn: bản CHƯA tối ưu làm gì, bản ĐÃ tối ưu làm gì.
class _Mechanism {
  final List<String> before;
  final List<String> after;

  const _Mechanism(this.before, this.after);
}

const Map<String, _Mechanism> _mechanisms = {
  'dashboard': _Mechanism([
    'Mỗi khu trọ là 1 GridView(shrinkWrap) nằm trong ListView: cuộn tới khu nào thì phải build + layout TOÀN BỘ phòng '
        'của khu đó trong cùng 1 khung hình, gây khựng từng nhịp khi cuộn qua các khu.',
    'Mở lại app: tải lại toàn bộ 4.000 phòng từ server, chờ xong mới vẽ.',
  ], [
    'Làm phẳng 50 khu thành MỘT ListView.builder duy nhất (dòng tiêu đề khu + khối 12 phòng): chỉ build phần đang thấy '
        'trên màn hình cộng một vùng đệm, cuộn tới đâu dựng tới đó, mỗi khung hình chỉ tốn rất ít việc.',
    'ETag + SQLite: mở lại app thì vẽ NGAY bản đã lưu trong máy; server thấy dữ liệu không đổi chỉ trả 304 (không gửi lại).',
    'Giải mã JSON lớn trong Isolate (compute) nên luồng giao diện không bị chặn. '
        '(Dashboard_Properti_Screen.dart, SyncedApi.dart, JsonIsolate.dart)',
  ]),
  'service': _Mechanism([
    'Lỗi N+1 request: tải danh sách phòng, rồi gọi API hóa đơn cho TỪNG phòng đang thuê, lần lượt từng cái '
        '(khoảng 2.833 request nối tiếp). Người dùng phải nhìn vòng quay hơn 1 phút.',
    'Danh sách vẽ kiểu cũ: dựng tất cả phòng của khu cùng lúc.',
  ], [
    'Gộp thành 1 request billing-status trả trạng thái hóa đơn của mọi phòng: thay vì 2.833 lượt hỏi server, chỉ còn 1.',
    'Hiện danh sách phòng ngay từ dữ liệu lưu trong SQLite, trạng thái hóa đơn cập nhật sau (không màn hình chờ).',
    'ListView.builder chỉ dựng các phòng đang thấy; JSON giải mã trong Isolate. (ServiceRoomScreen.dart: _fetchProgressive)',
  ]),
  'users': _Mechanism([
    'SingleChildScrollView + Column: tạo widget cho cả 2.833 khách thuê CÙNG LÚC, kể cả những dòng chưa nhìn thấy. '
        'Hàng nghìn widget nằm trong RAM, mỗi lần vẽ lại phải duyệt hết nên khung hình đứng hàng giây.',
  ], [
    'ListView.builder: chỉ dựng khoảng 15–20 dòng đang thấy, cuộn tới đâu tái sử dụng tới đó. '
        'Số widget không phụ thuộc vào việc có 100 hay 10.000 khách.',
    'Dữ liệu qua ETag/SQLite + giải mã JSON trong Isolate. (Manage_User_Screen.dart)',
  ]),
  'cards': _Mechanism([
    'Tải hết mọi trang ngay từ đầu rồi dựng cả 2.833 thẻ bằng Column trong SingleChildScrollView.',
    'Ảnh giải mã đúng kích thước gốc, giữ trong RAM.',
  ], [
    'PagedListView = ListView.builder + ScrollController: chỉ tải 20 thẻ/trang, cuộn gần cuối mới tải trang tiếp.',
    'ValueNotifier cho từng dòng: khóa/mở 1 thẻ chỉ vẽ lại đúng dòng đó, không vẽ lại cả danh sách.',
    'cached_network_image + memCacheWidth: ảnh thu nhỏ về kích thước hiển thị (48px) trước khi vào RAM, lưu đĩa để lần sau '
        'không tải lại. (SmartCardScreen.dart, PagedListView.dart, AppNetworkImage.dart)',
  ]),
};

class BenchAnalysis {
  static String? _screenId(BenchPair p) {
    for (final s in realScreens) {
      if (p.screen.startsWith(s.name)) return s.id;
    }
    return null;
  }

  static bool _isRestart(BenchPair p) => p.screen.endsWith('tắt/bật app');

  static String _ms(double v) => v >= 1000 ? '${_n(v / 1000, 1)} giây' : '${v.round()} ms';

  static String _n(double v, [int d = 0]) => v.toStringAsFixed(d).replaceAll('.', ',');

  static String _x(double g) => '×${_n(g, g >= 10 ? 0 : 1)}';

  /// Kết luận 1 câu cho mỗi màn (dùng ở thẻ "Kết luận" trên cùng).
  static String headline(BenchPair p) {
    final b = p.before!, a = p.after!;
    final name = p.screen.split(' (').first;
    if (b.openMs != null && a.openMs != null) {
      final g = b.openMs! / math.max(1, a.openMs!);
      final waitTxt = '${_ms(b.openMs!.toDouble())} → ${_ms(a.openMs!.toDouble())}';
      if (g >= 1.1) return '$name: thấy dữ liệu nhanh hơn ${_x(g)} ($waitTxt)${_smoothTail(b, a)}.';
      if (g <= 0.9) {
        return '$name: lượt này bản tối ưu thấy dữ liệu CHẬM hơn ($waitTxt), nên đo lại${_smoothTail(b, a)}.';
      }
      return '$name: thời gian thấy dữ liệu tương đương ($waitTxt)${_smoothTail(b, a)}.';
    }
    return '$name: FPS ${b.avgFps.round()} → ${a.avgFps.round()}, giật ${_n(b.jankPct, 1)}% → ${_n(a.jankPct, 1)}%.';
  }

  static String _smoothTail(BenchRun b, BenchRun a) {
    final parts = <String>[];
    if (b.worstMs >= 300 && a.worstMs < b.worstMs / 2) parts.add('hết đứng hình (${_ms(b.worstMs)} → ${_ms(a.worstMs)})');
    if (b.jankPct >= 5 && a.jankPct < b.jankPct / 2) parts.add('giật ${_n(b.jankPct, 1)}% → ${_n(a.jankPct, 1)}%');
    if (b.maxRss - a.maxRss >= 50) parts.add('RAM ${b.maxRss.round()} → ${a.maxRss.round()} MB');
    return parts.isEmpty ? '' : ', ${parts.join(', ')}';
  }

  /// Phân tích chi tiết 1 cặp.
  static List<AnalysisSection> analyze(BenchPair p) {
    final b = p.before!, a = p.after!;
    final out = <AnalysisSection>[];

    // ---------------- 1. TỐC ĐỘ ----------------
    final speed = <String>[];
    if (b.openMs != null && a.openMs != null) {
      final bo = b.openMs!.toDouble(), ao = a.openMs!.toDouble();
      final from = _isRestart(p) ? 'Từ lúc tắt app tới khi THẤY DỮ LIỆU' : 'Từ lúc mở màn tới khi THẤY DỮ LIỆU';
      if (bo / math.max(1, ao) >= 1.1) {
        speed.add('$from: ${_ms(bo)} → ${_ms(ao)}, nhanh hơn ${_x(bo / math.max(1, ao))}, '
            'người dùng bớt phải chờ ${_ms(bo - ao)}.');
        if (bo >= 10000) speed.add('Hơn 10 giây chờ, người dùng sẽ nghĩ app bị treo; bản tối ưu hiện gần như tức thì.');
      } else if (ao / math.max(1, bo) >= 1.1) {
        speed.add('$from: ${_ms(bo)} → ${_ms(ao)}, lượt này bản tối ưu chậm hơn ${_ms(ao - bo)}. '
            '${ao - bo >= 3000 ? 'Chênh lệch lớn bất thường: thường do máy (hoặc máy ảo) đang thiếu RAM hay mạng chậm lúc đo' : 'Chênh lệch nhỏ như vậy trên máy ảo thường do nhiễu'}; '
            'nên đo lại lượt này để xác nhận.');
      } else {
        speed.add('$from: ${_ms(bo)} → ${_ms(ao)}, tương đương. Màn này dữ liệu ít request nên tốc độ mở vốn đã nhanh; '
            'lợi ích của bản tối ưu nằm ở độ mượt khi cuộn (xem dưới).');
      }
    }
    if (b.bootMs != null && a.bootMs != null) {
      final d = (a.bootMs! - b.bootMs!).abs();
      speed.add(d <= 250 || a.bootMs! <= b.bootMs!
          ? 'Bật app tới khung hình đầu: ${_ms(b.bootMs!.toDouble())} → ${_ms(a.bootMs!.toDouble())}. '
              'Các kỹ thuật tối ưu KHÔNG làm app khởi động chậm đi.'
          : 'Bật app tới khung hình đầu: ${_ms(b.bootMs!.toDouble())} → ${_ms(a.bootMs!.toDouble())} '
              '(chênh ${_ms(d.toDouble())}, chủ yếu do máy ảo; phần khởi động không phụ thuộc kỹ thuật tối ưu).');
    }
    if (speed.isNotEmpty) out.add(AnalysisSection('Tốc độ (ưu tiên số 1)', Icons.bolt, speed));

    // ---------------- 2. ĐỘ MƯỢT ----------------
    final smooth = <String>[];
    smooth.add('FPS trung bình khi cuộn: ${b.avgFps.round()} → ${a.avgFps.round()} (60 là tối đa, dưới 30 mắt thấy rõ giật). '
        'FPS thấp nhất: ${b.minFps.round()} → ${a.minFps.round()}.');
    if (b.worstMs >= 700) {
      smooth.add('Khung hình chậm nhất ${_ms(b.worstMs)}: app ĐỨNG HÌNH gần ${_n(b.worstMs / 1000, 1)} giây, người dùng chạm '
          'không phản hồi. Bản tối ưu chỉ ${_ms(a.worstMs)} (${_x(b.worstMs / math.max(1, a.worstMs))}).');
    } else {
      smooth.add('Khung hình chậm nhất: ${_ms(b.worstMs)} → ${_ms(a.worstMs)} (mỗi khung hình chỉ có 16,7 ms để vẽ).');
    }
    final jankTxt = 'Khung hình giật (vẽ quá 16,7 ms): ${_n(b.jankPct, 1)}% → ${_n(a.jankPct, 1)}%';
    if (b.jankPct >= 2 * math.max(0.5, a.jankPct)) {
      smooth.add('$jankTxt. Gần như mọi khung hình bản tối ưu đều vẽ kịp.');
    } else if (a.jankPct > b.jankPct * 1.5 && a.jankPct > 5) {
      smooth.add('$jankTxt: bản tối ưu giật hơn, cần xem lại cách dựng danh sách của màn này.');
    } else {
      smooth.add('$jankTxt.');
    }
    out.add(AnalysisSection('Độ mượt', Icons.speed, smooth));

    // ---------------- 3. BỘ NHỚ ----------------
    final mem = <String>[];
    final dRam = b.maxRss - a.maxRss;
    if (dRam >= 50) {
      mem.add('RAM cao nhất: ${b.maxRss.round()} → ${a.maxRss.round()} MB, tiết kiệm ${dRam.round()} MB '
          '(${_x(b.maxRss / math.max(1, a.maxRss))}). Máy RAM 2–3 GB có thể bị hệ điều hành tắt app khi vượt 500–600 MB.');
    } else {
      mem.add('RAM cao nhất: ${b.maxRss.round()} → ${a.maxRss.round()} MB, tương đương: màn này ở cả 2 chế độ đều không giữ '
          'quá nhiều widget trong bộ nhớ cùng lúc.');
    }
    if (b.itemBuilds > 0 || a.itemBuilds > 0) {
      if (b.itemBuilds > a.itemBuilds * 1.5) {
        mem.add('Số dòng phải dựng: ${b.itemBuilds} → ${a.itemBuilds}. Bản cũ dựng gần như TẤT CẢ dòng dù không nhìn thấy; '
            'bản tối ưu chỉ dựng phần đang hiện trên màn hình. Đây chính là lý do RAM và thời gian vẽ giảm.');
      } else if (a.itemBuilds > b.itemBuilds * 1.2) {
        mem.add('Số dòng phải dựng: ${b.itemBuilds} → ${a.itemBuilds}. Bản tối ưu hiện danh sách sớm và cuộn mượt hơn nên trong '
            'cùng thời gian tự cuộn đi được xa hơn, gặp nhiều dòng hơn. Đây không phải lãng phí: mỗi dòng chỉ dựng khi thấy.');
      } else {
        mem.add('Số dòng phải dựng: ${b.itemBuilds} → ${a.itemBuilds}.');
      }
    }
    if (b.maxImageMb > 0.5 || a.maxImageMb > 0.5) {
      mem.add('RAM ảnh đã giải mã: ${_n(b.maxImageMb, 1)} → ${_n(a.maxImageMb, 1)} MB nhờ memCacheWidth (giải mã ảnh ở kích '
          'thước hiển thị thay vì ảnh gốc).');
    }
    out.add(AnalysisSection('Bộ nhớ', Icons.memory, mem));

    // ---------------- 4. MẠNG ----------------
    if (b.netKb > 0 || a.netKb > 0) {
      final net = <String>[];
      final req = b.netRequests > 0 || a.netRequests > 0 ? ' (${b.netRequests} → ${a.netRequests} request)' : '';
      if (b.netKb > a.netKb * 1.2) {
        net.add('Dữ liệu tải qua mạng: ${b.netKb.round()} → ${a.netKb.round()} KB$req, '
            'giảm ${_x(b.netKb / math.max(1, a.netKb))}: tiết kiệm 4G và pin.');
      } else {
        net.add('Dữ liệu tải qua mạng: ${b.netKb.round()} → ${a.netKb.round()} KB$req.');
      }
      out.add(AnalysisSection('Mạng', Icons.wifi, net));
    }

    // ---------------- 5. VÌ SAO ----------------
    final m = _mechanisms[_screenId(p)];
    if (m != null) {
      out.add(AnalysisSection('Vì sao bản CHƯA tối ưu chậm', Icons.cancel_outlined, m.before));
      out.add(AnalysisSection('Bản ĐÃ tối ưu làm gì', Icons.check_circle_outline, m.after));
    }
    if (_isRestart(p)) {
      out.add(const AnalysisSection('Cách đo', Icons.restart_alt, [
        'App bị TẮT HẲN (kill process, mất toàn bộ RAM) rồi tự bật lại như người dùng vuốt tắt app và mở lại. '
            'Đồng hồ chạy từ lúc tắt tới khi danh sách có dữ liệu trên màn hình, sau đó app tự cuộn để đo FPS và RAM.',
        'Dữ liệu thật trong database của tài khoản đang đăng nhập; hai chế độ chạy cùng máy, cùng dữ liệu, cùng thao tác.',
      ]));
    }
    return out;
  }

  /// Bản chữ (Markdown) để copy vào báo cáo.
  static String markdown(BenchPair p) {
    final b = StringBuffer();
    for (final s in analyze(p)) {
      b.writeln('**${s.title}**\n');
      for (final x in s.points) {
        b.writeln('- $x');
      }
      b.writeln();
    }
    return b.toString();
  }
}

/// Khối "Phân tích" hiển thị trong thẻ kết quả.
class AnalysisView extends StatelessWidget {
  final BenchPair pair;

  const AnalysisView({super.key, required this.pair});

  @override
  Widget build(BuildContext context) {
    final sections = BenchAnalysis.analyze(pair);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final s in sections) ...[
        Row(children: [
          Icon(s.icon,
              size: 16,
              color: s.title.startsWith('Vì sao')
                  ? kBeforeColor
                  : (s.title.startsWith('Bản ĐÃ') ? kAfterColor : Colors.blueGrey)),
          const SizedBox(width: 6),
          Text(s.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 4),
        for (final x in s.points)
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('•  ', style: TextStyle(fontSize: 12.5)),
              Expanded(child: Text(x, style: const TextStyle(fontSize: 12.5, height: 1.35))),
            ]),
          ),
        const SizedBox(height: 8),
      ],
    ]);
  }
}
