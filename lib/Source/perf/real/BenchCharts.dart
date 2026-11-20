// Đường dẫn: lib/Source/perf/real/BenchCharts.dart
//
// Biểu đồ so sánh CHƯA tối ưu (đỏ) và ĐÃ tối ưu (xanh), vẽ bằng Flutter thuần, không cần thư viện ngoài.
//  - CompareBarChart: mỗi chỉ số một cặp thanh ngang, dài theo tỉ lệ giá trị.
//  - CompareLineChart: diễn biến theo từng giây (FPS, RAM...) của 2 lần đo trên cùng một trục.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'RealBench.dart';

const Color kBeforeColor = Color(0xFFE53935); // Đỏ: CHƯA tối ưu
const Color kAfterColor = Color(0xFF43A047); // Xanh: ĐÃ tối ưu

class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key});

  Widget _item(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 14, height: 10, color: c),
        const SizedBox(width: 4),
        Text(t, style: const TextStyle(fontSize: 12)),
      ]);

  @override
  Widget build(BuildContext context) => Wrap(spacing: 16, children: [
        _item(kBeforeColor, 'CHƯA tối ưu'),
        _item(kAfterColor, 'ĐÃ tối ưu'),
      ]);
}

/// Biểu đồ cột ngang: mỗi chỉ số 2 thanh (đỏ/xanh) + giá trị + nhận xét tốt hơn/kém hơn.
class CompareBarChart extends StatelessWidget {
  final List<CompareMetric> metrics;

  const CompareBarChart({super.key, required this.metrics});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final m in metrics) ...[
        Row(children: [
          Expanded(child: Text(m.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
          Text(m.gainStr,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: m.better ? kAfterColor : ((m.gain ?? 1) <= 0.9 ? kBeforeColor : Colors.grey))),
        ]),
        const SizedBox(height: 2),
        _bar(m, m.before, kBeforeColor),
        const SizedBox(height: 2),
        _bar(m, m.after, kAfterColor),
        const SizedBox(height: 10),
      ],
    ]);
  }

  Widget _bar(CompareMetric m, double v, Color c) {
    final max = math.max(m.before, m.after);
    final frac = max <= 0 ? 0.0 : (v / max).clamp(0.0, 1.0);
    return LayoutBuilder(builder: (context, box) {
      const labelW = 86.0;
      final w = (box.maxWidth - labelW) * frac;
      return Row(children: [
        Container(
          width: math.max(2, w),
          height: 14,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 6),
        SizedBox(width: labelW - 6, child: Text(m.fmt(v), style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
      ]);
    });
  }
}

/// Biểu đồ đường theo thời gian (trục X = giây, trục Y = giá trị).
class CompareLineChart extends StatelessWidget {
  final String title;
  final String unit;
  final List<double> before;
  final List<double> after;
  final double? refLine; // Vạch tham chiếu (vd 60 FPS)
  final String? refLabel;

  const CompareLineChart({
    super.key,
    required this.title,
    required this.unit,
    required this.before,
    required this.after,
    this.refLine,
    this.refLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      SizedBox(
        height: 170,
        width: double.infinity,
        child: CustomPaint(painter: _LinePainter(before, after, unit, refLine, refLabel)),
      ),
      const SizedBox(height: 2),
      const Center(child: Text('thời gian (giây)', style: TextStyle(fontSize: 10, color: Colors.grey))),
    ]);
  }
}

class _LinePainter extends CustomPainter {
  final List<double> a; // CHƯA tối ưu
  final List<double> b; // ĐÃ tối ưu
  final String unit;
  final double? ref;
  final String? refLabel;

  _LinePainter(this.a, this.b, this.unit, this.ref, this.refLabel);

  @override
  void paint(Canvas canvas, Size size) {
    const left = 40.0, bottom = 16.0, top = 6.0, right = 6.0;
    final w = size.width - left - right;
    final h = size.height - top - bottom;
    final n = math.max(math.max(a.length, b.length), 2);
    var maxV = [...a, ...b, ref ?? 0].fold<double>(0, math.max);
    if (maxV <= 0) maxV = 1;
    maxV = _nice(maxV * 1.1);

    final axis = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 1;
    final grid = Paint()
      ..color = Colors.grey.shade200
      ..strokeWidth = 1;
    // Lưới ngang + nhãn trục Y
    for (var i = 0; i <= 4; i++) {
      final y = top + h - h * i / 4;
      canvas.drawLine(Offset(left, y), Offset(left + w, y), i == 0 ? axis : grid);
      _text(canvas, (maxV * i / 4).toStringAsFixed(0), Offset(0, y - 6), 9, Colors.grey.shade700, width: left - 4, alignRight: true);
    }
    canvas.drawLine(Offset(left, top), Offset(left, top + h), axis);
    // Nhãn trục X
    for (var i = 0; i < n; i += math.max(1, (n / 6).ceil())) {
      final x = left + w * i / (n - 1);
      _text(canvas, '$i', Offset(x - 6, top + h + 2), 9, Colors.grey.shade700);
    }
    _text(canvas, unit, Offset(left + 4, top), 9, Colors.grey.shade600);

    if (ref != null) {
      final y = top + h - h * (ref! / maxV);
      final p = Paint()
        ..color = Colors.blueGrey.shade200
        ..strokeWidth = 1;
      for (double x = left; x < left + w; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, left + w), y), p);
      }
      if (refLabel != null) _text(canvas, refLabel!, Offset(left + w - 60, y - 12), 9, Colors.blueGrey);
    }

    void line(List<double> v, Color c) {
      if (v.isEmpty) return;
      final path = Path();
      for (var i = 0; i < v.length; i++) {
        final x = left + w * i / (n - 1);
        final y = top + h - h * (v[i] / maxV).clamp(0.0, 1.0);
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = c
            ..strokeWidth = 2.2
            ..style = PaintingStyle.stroke);
    }

    line(a, kBeforeColor);
    line(b, kAfterColor);
  }

  static double _nice(double v) {
    final mag = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    for (final m in [1, 2, 2.5, 5, 10]) {
      if (m * mag >= v) return m * mag;
    }
    return 10 * mag;
  }

  void _text(Canvas c, String s, Offset o, double size, Color color, {double? width, bool alignRight = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size, color: color)),
      textDirection: TextDirection.ltr,
      textAlign: alignRight ? TextAlign.right : TextAlign.left,
    )..layout(minWidth: width ?? 0, maxWidth: width ?? 200);
    tp.paint(c, o);
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => old.a != a || old.b != b;
}

/// Biểu đồ tổng quan: 1 chỉ số của mọi màn hình (mỗi màn 1 cặp cột dọc).
class OverviewBarChart extends StatelessWidget {
  final String title;
  final String unit;
  final List<(String, double, double)> items; // (tên màn, chưa tối ưu, đã tối ưu)

  const OverviewBarChart({super.key, required this.title, required this.unit, required this.items});

  @override
  Widget build(BuildContext context) {
    final maxV = items.fold<double>(0, (m, e) => math.max(m, math.max(e.$2, e.$3)));
    String f(double v) => v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$title ($unit)', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      SizedBox(
        height: 150,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final e in items)
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
                  _col(e.$2, maxV, kBeforeColor, f),
                  const SizedBox(width: 3),
                  _col(e.$3, maxV, kAfterColor, f),
                ]),
                const SizedBox(height: 4),
                Text(e.$1, style: const TextStyle(fontSize: 10), textAlign: TextAlign.center, maxLines: 2),
              ]),
            ),
        ]),
      ),
    ]);
  }

  Widget _col(double v, double maxV, Color c, String Function(double) f) {
    final hgt = maxV <= 0 ? 2.0 : math.max(2.0, 100 * v / maxV);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(f(v), style: const TextStyle(fontSize: 9)),
      Container(width: 18, height: hgt, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
    ]);
  }
}
