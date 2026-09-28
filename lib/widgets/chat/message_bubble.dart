import 'package:flutter/material.dart';

import '../../models/chat_message.dart';
import '../../theme/effective_bubble_theme.dart';
import 'chat_bubble_surface.dart';

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
    final bubbleTheme = effectiveBubbleTheme(context);
    return GestureDetector(
      onLongPress: onLongPress,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.72,
        ),
        child: ChatBubbleSurface(
          theme: bubbleTheme,
          isUser: isUser,
          showTail: showTail,
          isRedPacket: isRedPacket,
          isError: message.role == 'error',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!message.isRecalled && message.source == 'initiative') ...[
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
      ),
    );
  }

  static Color textColorForRole(String role) {
    if (role == 'error') return Colors.red.shade700;
    return const Color(0xFF171717);
  }
}
