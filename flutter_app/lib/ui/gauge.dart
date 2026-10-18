import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Speedometer: a 240° arc from 0 to 160 km/h with the speed in the middle.
/// Drawn in a 300 x 230 design space (same geometry as the web version) and scaled to fit.
class GaugeView extends StatelessWidget {
  const GaugeView({super.key, required this.speed});

  final double speed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Semantics(
          label: 'Speed ${speed.round()} kilometres per hour',
          child: AspectRatio(
            aspectRatio: 300 / 230,
            child: CustomPaint(painter: GaugePainter(speed)),
          ),
        ),
      ),
    );
  }
}

class GaugePainter extends CustomPainter {
  GaugePainter(this.speed);

  final double speed;

  static const double maxSpeed = 160;
  static const Offset center = Offset(150, 140);
  static const double radius = 110;
  static const double startDeg = 150;
  static const double sweepDeg = 240;

  static double _rad(double deg) => deg * math.pi / 180;

  static Offset _point(double r, double deg) =>
      Offset(center.dx + r * math.cos(_rad(deg)), center.dy + r * math.sin(_rad(deg)));

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 300);

    final rect = Rect.fromCircle(center: center, radius: radius);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;

    // Track
    canvas.drawArc(rect, _rad(startDeg), _rad(sweepDeg), false, stroke..color = Palette.track);

    // Value: green -> yellow -> red, fixed across the whole gauge
    final fraction = (speed / maxSpeed).clamp(0.0, 1.0);
    if (fraction > 0.004) {
      final fg = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..strokeCap = StrokeCap.round
        ..shader = ui.Gradient.linear(
          const Offset(40, 0),
          const Offset(260, 0),
          const [Palette.accent, Palette.warn, Palette.danger],
          const [0, 0.6, 1],
        );
      canvas.drawArc(rect, _rad(startDeg), _rad(sweepDeg * fraction), false, fg);
    }

    // Ticks and numbers
    for (var v = 0; v <= maxSpeed.toInt(); v += 10) {
      final deg = startDeg + v / maxSpeed * sweepDeg;
      final major = v % 20 == 0;
      canvas.drawLine(
        _point(radius - 14, deg),
        _point(radius - (major ? 24 : 19), deg),
        Paint()
          ..color = major ? const Color(0xFF6B7684) : const Color(0xFF3A4350)
          ..strokeWidth = major ? 3 : 2,
      );
      if (major) {
        _text(canvas, '$v', _point(radius - 36, deg), mono(size: 12, color: Palette.muted));
      }
    }

    // Speed
    _text(canvas, '${speed.round()}', const Offset(150, 118), mono(size: 76, weight: FontWeight.w700, color: Colors.white));
    _text(canvas, 'km/h', const Offset(150, 176), const TextStyle(fontSize: 14, letterSpacing: 2, color: Palette.muted));

    canvas.restore();
  }

  void _text(Canvas canvas, String text, Offset at, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(GaugePainter old) => old.speed.round() != speed.round() ||
      (old.speed / maxSpeed * 240).round() != (speed / maxSpeed * 240).round();
}
