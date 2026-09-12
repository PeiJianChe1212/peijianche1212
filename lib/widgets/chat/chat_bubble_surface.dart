import 'package:flutter/material.dart';
import '../../theme/chat_visual_theme.dart';
import '../../theme/app_dimensions.dart';
import '../../theme/app_spacing.dart';

/// Shared visual shell for live messages and appearance previews.
class ChatBubbleSurface extends StatelessWidget {
  const ChatBubbleSurface({
    super.key,
    required this.theme,
    required this.isUser,
    required this.child,
    this.showTail = true,
    this.isRedPacket = false,
    this.isError = false,
  });
  final ChatBubbleTheme theme;
  final bool isUser, showTail, isRedPacket, isError;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final decoration = isRedPacket
        ? BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
            boxShadow: const [],
          )
        : isError
        ? BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(theme.borderRadius),
            boxShadow: const [
              BoxShadow(
                color: Color(0x06000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          )
        : theme.decoration(isUser: isUser);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (!isRedPacket &&
            !isError &&
            showTail &&
            theme.tailStyle != ChatBubbleTailStyle.none)
          Positioned(
            left: isUser
                ? null
                : (theme.tailStyle == ChatBubbleTailStyle.rounded ? -7 : -4),
            right: isUser
                ? (theme.tailStyle == ChatBubbleTailStyle.rounded ? -7 : -4)
                : null,
            top: theme.tailStyle == ChatBubbleTailStyle.softRound ? 22 : 10,
            child: CustomPaint(
              size: theme.tailStyle == ChatBubbleTailStyle.rounded
                  ? const Size(12, 14)
                  : const Size(8, 10),
              painter: _BubbleTailPainter(
                color: decoration.color!,
                pointsRight: !isUser,
                style: theme.tailStyle,
              ),
            ),
          ),
        Container(
          margin: const EdgeInsets.symmetric(vertical: 2.5),
          padding: isRedPacket
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 8,
                ),
          decoration: decoration,
          child: child,
        ),
      ],
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  const _BubbleTailPainter({
    required this.color,
    required this.pointsRight,
    required this.style,
  });

  final Color color;
  final bool pointsRight;
  final ChatBubbleTailStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (style != ChatBubbleTailStyle.rounded) {
      canvas.save();
      if (!pointsRight) {
        canvas.translate(size.width, 0);
        canvas.scale(-1, 1);
      }
      if (style == ChatBubbleTailStyle.brandWing) {
        path
          ..moveTo(size.width, 0)
          ..quadraticBezierTo(
            size.width * .45,
            size.height * .18,
            0,
            size.height * .74,
          )
          ..quadraticBezierTo(
            size.width * .48,
            size.height * .64,
            size.width,
            size.height,
          )
          ..close();
      } else {
        path
          ..moveTo(size.width, 0)
          ..cubicTo(
            size.width * .82,
            size.height * .35,
            0,
            size.height * .42,
            0,
            size.height * .72,
          )
          ..quadraticBezierTo(0, size.height, size.width, size.height)
          ..close();
      }
      canvas.drawPath(path, Paint()..color = color);
      canvas.restore();
      return;
    }

    if (pointsRight) {
      path
        ..moveTo(size.width, 0)
        ..cubicTo(size.width * 0.65, 2, size.width * 0.5, 7, 0, size.height)
        ..cubicTo(
          size.width * 0.62,
          size.height - 2,
          size.width * 0.9,
          9,
          size.width,
          7,
        )
        ..close();
    } else {
      path
        ..moveTo(0, 0)
        ..cubicTo(
          size.width * 0.35,
          2,
          size.width * 0.5,
          7,
          size.width,
          size.height,
        )
        ..cubicTo(size.width * 0.38, size.height - 2, size.width * 0.1, 9, 0, 7)
        ..close();
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BubbleTailPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.pointsRight != pointsRight ||
      oldDelegate.style != style;
}
