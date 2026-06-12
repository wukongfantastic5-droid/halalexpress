import 'package:flutter/material.dart';

class BunnyIcon extends StatelessWidget {
  final double size;
  final Color color;
  final Color? accentColor;

  const BunnyIcon({
    super.key,
    this.size = 48,
    this.color = Colors.white,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _BunnyPainter(
          color: color,
          accentColor: accentColor,
        ),
      ),
    );
  }
}

class _BunnyPainter extends CustomPainter {
  final Color color;
  final Color? accentColor;

  _BunnyPainter({required this.color, this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final w = size.width;
    final scale = h / 100;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final earPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final innerEarPaint = Paint()
      ..color = (accentColor ?? color).withOpacity(0.3)
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.translate(w / 2, h / 2 - 2 * scale);

    // --- Left ear ---
    canvas.save();
    canvas.rotate(-0.18);
    final earPath = Path()
      ..moveTo(-8 * scale, -30 * scale)
      ..quadraticBezierTo(
        -12 * scale, -55 * scale,
        0 * scale, -58 * scale,
      )
      ..quadraticBezierTo(
        10 * scale, -55 * scale,
        6 * scale, -30 * scale,
      )
      ..close();
    canvas.drawPath(earPath, earPaint);
    canvas.restore();

    // --- Right ear ---
    canvas.save();
    canvas.rotate(0.18);
    final earPathR = Path()
      ..moveTo(-6 * scale, -30 * scale)
      ..quadraticBezierTo(
        -10 * scale, -55 * scale,
        0 * scale, -58 * scale,
      )
      ..quadraticBezierTo(
        12 * scale, -55 * scale,
        8 * scale, -30 * scale,
      )
      ..close();
    canvas.drawPath(earPathR, earPaint);
    canvas.restore();

    // --- Inner left ear ---
    canvas.save();
    canvas.rotate(-0.18);
    final innerEarPath = Path()
      ..moveTo(-4 * scale, -32 * scale)
      ..quadraticBezierTo(
        -6 * scale, -50 * scale,
        0 * scale, -52 * scale,
      )
      ..quadraticBezierTo(
        5 * scale, -50 * scale,
        3 * scale, -32 * scale,
      )
      ..close();
    canvas.drawPath(innerEarPath, innerEarPaint);
    canvas.restore();

    // --- Inner right ear ---
    canvas.save();
    canvas.rotate(0.18);
    final innerEarPathR = Path()
      ..moveTo(-3 * scale, -32 * scale)
      ..quadraticBezierTo(
        -5 * scale, -50 * scale,
        0 * scale, -52 * scale,
      )
      ..quadraticBezierTo(
        6 * scale, -50 * scale,
        4 * scale, -32 * scale,
      )
      ..close();
    canvas.drawPath(innerEarPathR, innerEarPaint);
    canvas.restore();

    // --- Head (circle) ---
    canvas.drawCircle(Offset(0, 2 * scale), 28 * scale, fillPaint);

    // --- Eyes ---
    final eyePaint = Paint()
      ..color = color.computeLuminance() > 0.5
          ? Colors.black87
          : Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(-10 * scale, -5 * scale), 3.6 * scale, eyePaint);
    canvas.drawCircle(Offset(10 * scale, -5 * scale), 3.6 * scale, eyePaint);

    // Eye shine
    final eyeShinePaint = Paint()
      ..color = color.computeLuminance() > 0.5
          ? Colors.white
          : Colors.black26
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(-8 * scale, -7 * scale), 1.2 * scale, eyeShinePaint);
    canvas.drawCircle(Offset(12 * scale, -7 * scale), 1.2 * scale, eyeShinePaint);

    // --- Nose ---
    final nosePaint = Paint()
      ..color = color.computeLuminance() > 0.5
          ? const Color(0xFFFF8A80)
          : const Color(0xFFEF9A9A)
      ..style = PaintingStyle.fill;
    final nosePath = Path()
      ..moveTo(0, 3 * scale)
      ..lineTo(-4 * scale, 7 * scale)
      ..lineTo(4 * scale, 7 * scale)
      ..close();
    canvas.drawPath(nosePath, nosePaint);

    // --- Mouth ---
    final mouthPaint = Paint()
      ..color = color.computeLuminance() > 0.5
          ? Colors.black54
          : Colors.white54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 * scale
      ..strokeCap = StrokeCap.round;
    final mouthPath = Path()
      ..moveTo(-6 * scale, 9 * scale)
      ..quadraticBezierTo(-3 * scale, 14 * scale, 0, 11 * scale)
      ..quadraticBezierTo(3 * scale, 14 * scale, 6 * scale, 9 * scale);
    canvas.drawPath(mouthPath, mouthPaint);

    // --- Whiskers ---
    final whiskerPaint = Paint()
      ..color = color.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 * scale
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(-14 * scale, 1 * scale),
      Offset(-25 * scale, -2 * scale),
      whiskerPaint,
    );
    canvas.drawLine(
      Offset(-14 * scale, 5 * scale),
      Offset(-25 * scale, 5 * scale),
      whiskerPaint,
    );
    canvas.drawLine(
      Offset(-14 * scale, 9 * scale),
      Offset(-25 * scale, 12 * scale),
      whiskerPaint,
    );
    canvas.drawLine(
      Offset(14 * scale, 1 * scale),
      Offset(25 * scale, -2 * scale),
      whiskerPaint,
    );
    canvas.drawLine(
      Offset(14 * scale, 5 * scale),
      Offset(25 * scale, 5 * scale),
      whiskerPaint,
    );
    canvas.drawLine(
      Offset(14 * scale, 9 * scale),
      Offset(25 * scale, 12 * scale),
      whiskerPaint,
    );

    // --- Cheeks ---
    final cheekPaint = Paint()
      ..color = (color.computeLuminance() > 0.5
              ? const Color(0xFFFFAB91)
              : const Color(0xFFEF9A9A))
          .withOpacity(0.25)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(-18 * scale, 5 * scale), 5 * scale, cheekPaint);
    canvas.drawCircle(Offset(18 * scale, 5 * scale), 5 * scale, cheekPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BunnyPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.accentColor != accentColor;
  }
}
