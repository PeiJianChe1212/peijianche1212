import 'package:flutter/material.dart';

import '../../models/chat_message.dart';
import '../../services/peilink_appearance_service.dart';
import '../../theme/app_dimensions.dart';
import '../../theme/app_spacing.dart';
import '../../theme/chat_visual_theme.dart';

/// 聊天消息的通用气泡外壳。
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isUser,
    required this.showTail,
    required this.onLongPress,
    required this.child,
  });

  final ChatMessage message;
  final bool isUser;
  final bool showTail;
  final VoidCallback onLongPress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final textColor = textColorForRole(message.role);
    final isRedPacket = message.type == MessageType.redPacket;
    final bubbleTheme = PeiLinkAppearanceScope.of(context).bubbleTheme;
    final bubbleColor = _bubbleColor(message.role, bubbleTheme);
    final hasTail =
        !isRedPacket &&
        showTail &&
        bubbleTheme.tailStyle == ChatBubbleTailStyle.rounded &&
        message.role != 'error';

    return GestureDetector(
      onLongPress: onLongPress,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.72,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (hasTail)
              Positioned(
                left: isUser ? null : -7,
                right: isUser ? -7 : null,
                top: 10,
                child: CustomPaint(
                  size: const Size(12, 14),
                  painter: _BubbleTailPainter(
                    color: bubbleColor,
                    pointsRight: !isUser,
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
              decoration: BoxDecoration(
                color: isRedPacket ? Colors.transparent : bubbleColor,
                borderRadius: BorderRadius.circular(
                  isRedPacket
                      ? AppDimensions.radiusLarge
                      : bubbleTheme.borderRadius,
                ),
                boxShadow: isRedPacket
                    ? const []
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.025),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!message.isRecalled &&
                      message.source == 'initiative') ...[
                    Text(
                      '他主动发来的',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: textColor.withValues(alpha: 0.46),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(child: child),
                      if (!message.isRecalled && message.isFavorite) ...[
                        const SizedBox(width: 7),
                        const Icon(
                          Icons.favorite_rounded,
                          size: 13,
                          color: Color(0xFFCB718E),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Color textColorForRole(String role) {
    if (role == 'error') return Colors.red.shade700;
    return const Color(0xFF171717);
  }

  static Color _bubbleColor(String role, ChatBubbleTheme theme) {
    if (role == 'user') return theme.userBubbleColor;
    if (role == 'error') return Colors.red.shade50;
    return theme.aiBubbleColor;
  }
}

class _BubbleTailPainter extends CustomPainter {
  const _BubbleTailPainter({required this.color, required this.pointsRight});

  final Color color;
  final bool pointsRight;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
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
      oldDelegate.color != color || oldDelegate.pointsRight != pointsRight;
}
