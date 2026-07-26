import 'package:flutter/material.dart';

import '../../models/chat_message.dart';
import 'message_bubble.dart';
import 'renderers/image_message_renderer.dart';
import 'renderers/text_message_renderer.dart';

/// 聊天消息的统一渲染入口。
///
/// 每条消息先在这里根据类型选择显示方式，再套上统一的气泡和头像。
/// 当前只有文本显示器，因此其他预留类型暂时也会安全地按文本显示。
class MessageRenderer extends StatelessWidget {
  const MessageRenderer({
    super.key,
    required this.message,
    required this.onLongPress,
    required this.assistantAvatar,
    required this.userAvatar,
    this.onAssistantAvatarTap,
    this.onUserAvatarTap,
  });

  final ChatMessage message;
  final VoidCallback onLongPress;
  final Widget assistantAvatar;
  final Widget userAvatar;
  final VoidCallback? onAssistantAvatarTap;
  final VoidCallback? onUserAvatarTap;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final isAssistant = message.role == 'assistant';

    if (message.type == MessageType.system || message.role == 'system') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 28),
        child: Row(
          children: [
            Expanded(
              child: Divider(
                height: 1,
                thickness: 0.6,
                color: Colors.black.withValues(alpha: 0.10),
              ),
            ),
            const SizedBox(width: 14),
            Flexible(
              flex: 4,
              child: Text(
                message.content,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.42),
                  fontSize: 12.5,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Divider(
                height: 1,
                thickness: 0.6,
                color: Colors.black.withValues(alpha: 0.10),
              ),
            ),
          ],
        ),
      );
    }

    final bubble = MessageBubble(
      message: message,
      isUser: isUser,
      onLongPress: onLongPress,
      child: _buildMessageContent(),
    );

    if (!isAssistant && !isUser) {
      return Align(alignment: Alignment.centerLeft, child: bubble);
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onAssistantAvatarTap,
              child: assistantAvatar,
            ),
            const SizedBox(width: 7),
          ],
          Flexible(child: bubble),
          if (isUser) ...[
            const SizedBox(width: 7),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onUserAvatarTap,
              child: userAvatar,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageContent() {
    switch (message.type) {
      case MessageType.text:
        return TextMessageRenderer(message: message);
      case MessageType.image:
        return ImageMessageRenderer(message: message);
      case MessageType.voice:
      case MessageType.system:
      case MessageType.card:
        return TextMessageRenderer(message: message);
    }
  }
}
