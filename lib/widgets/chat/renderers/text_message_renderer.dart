import 'package:flutter/material.dart';

import '../../../conversation/message_content_parser.dart';
import '../../../models/chat_message.dart';
import '../message_bubble.dart';

class TextMessageRenderer extends StatelessWidget {
  const TextMessageRenderer({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final segments = MessageContentParser.parse(message.content);
    final speechColor = MessageBubble.textColorForRole(message.role);
    final asideColor = message.role == 'error'
        ? speechColor.withValues(alpha: 0.62)
        : const Color(0xFF8A8A8A);

    return Text.rich(
      TextSpan(
        children: segments.map((segment) {
          return TextSpan(
            text: segment.text,
            style: TextStyle(
              fontSize: 16,
              height: 1.42,
              fontStyle: FontStyle.normal,
              fontWeight: segment.isAside
                  ? FontWeight.w400
                  : FontWeight.w600,
              color: segment.isAside ? asideColor : speechColor,
            ),
          );
        }).toList(),
      ),
    );
  }
}
