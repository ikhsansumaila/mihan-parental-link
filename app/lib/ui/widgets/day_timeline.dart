import 'package:flutter/material.dart';

import '../../core/schedule.dart';

/// Bar 24 jam: blok hijau = boleh pakai, sisanya = terkunci.
class DayTimeline extends StatelessWidget {
  final List<TimeWindow> windows;
  final double height;
  final bool showLabels;

  /// Jika diisi, tampilkan garis "sekarang" (menit sejak 00:00).
  final int? nowMinute;

  const DayTimeline({
    super.key,
    required this.windows,
    this.height = 14,
    this.showLabels = false,
    this.nowMinute,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bar = SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _TimelinePainter(
          windows: windows,
          allowed: const Color(0xFF34A853),
          locked: cs.surfaceContainerHighest,
          tick: cs.outlineVariant,
          now: nowMinute,
          nowColor: cs.error,
        ),
      ),
    );
    if (!showLabels) return bar;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      bar,
      const SizedBox(height: 2),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [for (final h in ['00', '06', '12', '18', '24']) Text(h, style: style)],
      ),
    ]);
  }
}

class _TimelinePainter extends CustomPainter {
  final List<TimeWindow> windows;
  final Color allowed, locked, tick, nowColor;
  final int? now;

  _TimelinePainter({
    required this.windows,
    required this.allowed,
    required this.locked,
    required this.tick,
    required this.now,
    required this.nowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 3);
    final full = RRect.fromRectAndRadius(Offset.zero & size, r);
    canvas.save();
    canvas.clipRRect(full);
    canvas.drawRect(Offset.zero & size, Paint()..color = locked);
    final p = Paint()..color = allowed;
    for (final w in windows) {
      final x0 = size.width * w.start / 1440, x1 = size.width * w.end / 1440;
      canvas.drawRect(Rect.fromLTRB(x0, 0, x1, size.height), p);
    }
    final tp = Paint()
      ..color = tick
      ..strokeWidth = 1;
    for (var h = 6; h < 24; h += 6) {
      final x = size.width * h / 24;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), tp);
    }
    canvas.restore();
    if (now != null) {
      final x = size.width * now! / 1440;
      canvas.drawLine(
        Offset(x, -2),
        Offset(x, size.height + 2),
        Paint()
          ..color = nowColor
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) =>
      old.windows != windows || old.now != now || old.allowed != allowed || old.locked != locked;
}
