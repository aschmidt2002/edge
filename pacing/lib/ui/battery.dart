import 'package:flutter/material.dart';

import 'common.dart';

/// The energy battery: a horizontal cell with a terminal, filled to [share].
class BatteryGauge extends StatelessWidget {
  const BatteryGauge({super.key, required this.share, this.height = 72});
  final double share;
  final double height;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Energie-Akku ${(share * 100).round()} Prozent',
      child: SizedBox(
        height: height,
        child: CustomPaint(
          painter: _BatteryPainter(
            share.clamp(0.0, 1.0),
            fill: batteryColor(share, s),
            outline: s.onSurfaceVariant,
            empty: s.surfaceContainerHighest,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _BatteryPainter extends CustomPainter {
  _BatteryPainter(this.share,
      {required this.fill, required this.outline, required this.empty});
  final double share;
  final Color fill;
  final Color outline;
  final Color empty;

  @override
  void paint(Canvas canvas, Size size) {
    final tip = size.height * 0.12;
    final body = Rect.fromLTWH(0, 0, size.width - tip - 4, size.height);
    final r = Radius.circular(size.height * 0.18);
    final stroke = Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRRect(RRect.fromRectAndRadius(body, r), stroke);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(body.right + 2, size.height * 0.3, tip,
            size.height * 0.4),
        Radius.circular(tip / 2),
      ),
      Paint()..color = outline,
    );
    final inner = body.deflate(7);
    final ir = Radius.circular(size.height * 0.12);
    canvas.drawRRect(
        RRect.fromRectAndRadius(inner, ir), Paint()..color = empty);
    if (share > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(inner.left, inner.top, inner.width * share,
              inner.height),
          ir,
        ),
        Paint()..color = fill,
      );
    }
  }

  @override
  bool shouldRepaint(_BatteryPainter o) =>
      o.share != share || o.fill != fill || o.outline != outline;
}
