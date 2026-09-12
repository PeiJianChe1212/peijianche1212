import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'theme_background.dart';

/// Identical background composition for pages and thumbnails.
class ThemeBackgroundSurface extends StatelessWidget {
  const ThemeBackgroundSurface({
    super.key,
    required this.background,
    this.image,
    this.imageFit = BoxFit.cover,
  });
  final ThemeBackground background;
  final ImageProvider<Object>? image;
  final BoxFit imageFit;
  @override
  Widget build(BuildContext context) {
    final resolved =
        image ??
        (background.imagePath == null
            ? null
            : AssetImage(background.imagePath!));
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          key: ValueKey('theme-background-${background.id}'),
          decoration: BoxDecoration(gradient: background.gradient),
        ),
        if (resolved != null)
          Opacity(
            opacity: background.opacity,
            child: Image(image: resolved, fit: imageFit),
          ),
        if (background.pattern != null)
          RepaintBoundary(
            child: CustomPaint(painter: _PatternPainter(background.pattern!)),
          ),
      ],
    );
  }
}

class _PatternPainter extends CustomPainter {
  const _PatternPainter(this.pattern);
  final BackgroundPattern pattern;
  @override
  void paint(Canvas canvas, Size size) {
    // One deterministic portrait composition, cropped like an image in thumbnails.
    final scale = math.max(size.width / 360, size.height / 780);
    canvas.save();
    canvas.translate(
      (size.width - 360 * scale) / 2,
      (size.height - 780 * scale) / 2,
    );
    canvas.scale(scale);
    final paint = Paint()
      ..color = const Color(0x19788EA8)
      ..strokeWidth = .8;
    for (var i = 0; i < 32; i++) {
      final x = 18.0 + (i * 97 % 328);
      final y = 24.0 + (i * 151 % 732);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate((i % 5 - 2) * .25);
      switch (pattern) {
        case BackgroundPattern.butterfly:
          paint.color = const Color(0x1A8B8DBA);
          canvas.drawOval(const Rect.fromLTWH(-9, -6, 8, 11), paint);
          canvas.drawOval(const Rect.fromLTWH(1, -6, 8, 11), paint);
          canvas.drawLine(const Offset(0, -4), const Offset(0, 7), paint);
        case BackgroundPattern.petals:
          paint.color = const Color(0x1FD99DB0);
          canvas.drawPath(
            Path()
              ..moveTo(0, -7)
              ..quadraticBezierTo(11, 0, 0, 9)
              ..quadraticBezierTo(-6, 0, 0, -7),
            paint,
          );
        case BackgroundPattern.osmanthus:
          paint.color = const Color(0x28BEA16D);
          for (var j = 0; j < 4; j++) {
            canvas.drawOval(const Rect.fromLTWH(-2, -6, 4, 6), paint);
            canvas.rotate(math.pi / 2);
          }
        case BackgroundPattern.ginkgo:
          paint.color = const Color(0x258FA77E);
          canvas.drawPath(
            Path()
              ..moveTo(0, 7)
              ..lineTo(-9, -4)
              ..quadraticBezierTo(0, -12, 9, -4)
              ..close(),
            paint,
          );
          canvas.drawLine(const Offset(0, 7), const Offset(0, 12), paint);
        case BackgroundPattern.snow:
          paint.color = const Color(0xCFFFFFFF);
          for (var j = 0; j < 3; j++) {
            canvas.drawLine(const Offset(-3, 0), const Offset(3, 0), paint);
            canvas.rotate(math.pi / 3);
          }
        case BackgroundPattern.rain:
          paint.color = const Color(0x16819BAA);
          canvas.drawOval(const Rect.fromLTWH(-2, -7, 4, 12), paint);
          paint.color = const Color(0xA0FFFFFF);
          canvas.drawLine(const Offset(-1, -5), const Offset(-1, 1), paint);
        case BackgroundPattern.waves:
          paint.color = const Color(0x2081A8B1);
          paint.style = PaintingStyle.stroke;
          canvas.drawPath(
            Path()
              ..moveTo(-18, 0)
              ..cubicTo(-8, -5, 6, 5, 18, 0),
            paint,
          );
          paint.style = PaintingStyle.fill;
        case BackgroundPattern.aurora:
          paint.color = i.isEven
              ? const Color(0x208993CD)
              : const Color(0x2094BEAD);
          canvas.drawCircle(Offset.zero, i % 3 + 1.5, paint);
          canvas.drawLine(const Offset(-5, 0), const Offset(5, 0), paint);
      }
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PatternPainter oldDelegate) =>
      oldDelegate.pattern != pattern;
}
