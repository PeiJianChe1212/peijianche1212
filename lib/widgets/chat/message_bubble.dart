import 'package:flutter/material.dart';

import '../../models/chat_message.dart';

/// 聊天消息的通用气泡外壳。
///
/// 只负责所有消息共有的视觉和交互：尺寸、间距、背景、圆角、阴影、
/// 主动消息提示、收藏标记与长按入口。具体消息内容由 [child] 提供。
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
          maxWidth: MediaQuery.sizeOf(context).width * 0.68,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _bubbleColor(message.role),
            borderRadius: _bubbleBorderRadius(isUser),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 4,
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
                    color: textColor.withValues(alpha: 0.48),
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

  /// 供内容渲染器复用的文字颜色规则。
  static Color textColorForRole(String role) {
    if (role == 'error') return Colors.red.shade700;
    return Colors.black87;
  }

  static Color _bubbleColor(String role) {
    if (role == 'user') return const Color(0xFF9DD1F4);
    if (role == 'error') return Colors.red.shade50;
    return Colors.grey.shade200;
  }

  static BorderRadius _bubbleBorderRadius(bool isUser) {
    return BorderRadius.only(
      topLeft: const Radius.circular(17),
      topRight: const Radius.circular(17),
      bottomLeft: Radius.circular(isUser ? 17 : 5),
      bottomRight: Radius.circular(isUser ? 5 : 17),
    );
  }
}
