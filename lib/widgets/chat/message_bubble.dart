import 'package:flutter/material.dart';

import '../../models/chat_message.dart';

/// 聊天消息的通用气泡外壳。
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isUser,
    required this.onLongPress,
    required this.child,
  });

  final ChatMessage message;
  final bool isUser;
  final VoidCallback onLongPress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final textColor = textColorForRole(message.role);

    return GestureDetector(
      onLongPress: onLongPress,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.72,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3.5),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9.5),
          decoration: BoxDecoration(
            color: _bubbleColor(message.role),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.black.withValues(alpha: 0.045),
              width: 0.55,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.025),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.source == 'initiative') ...[
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
                  if (message.isFavorite) ...[
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

  static Color _bubbleColor(String role) {
    if (role == 'user') return const Color(0xFF95EC69);
    if (role == 'error') return Colors.red.shade50;
    return const Color(0xFFFFFFFF);
  }
}
