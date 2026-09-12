import 'package:flutter/material.dart';

import '../../../conversation/message_content_parser.dart';
import '../../../models/chat_message.dart';
import '../../../services/peilink_appearance_service.dart';
import '../message_bubble.dart';

class TextMessageRenderer extends StatelessWidget {
  const TextMessageRenderer({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final fontTheme = PeiLinkAppearanceScope.of(
      context,
    ).fontTheme.effectiveFont;
    final isBody =
        (message.role == 'user' || message.role == 'assistant') &&
        message.type != MessageType.system;
    final speechColor = MessageBubble.textColorForRole(message.role);
    final asideColor = message.role == 'error'
        ? speechColor.withValues(alpha: 0.62)
        : const Color(0xFF8A8A8A);

    TextSpan plain(String text) => TextSpan(
      children: MessageContentParser.parse(text)
          .map(
            (segment) => TextSpan(
              text: segment.text,
              style: TextStyle(
                fontSize: 16,
                height: 1.42,
                fontStyle: FontStyle.normal,
                fontFamily: isBody ? fontTheme.fontFamily : null,
                fontFamilyFallback: isBody
                    ? fontTheme.fontFamilyFallback
                    : null,
                fontWeight: segment.isAside
                    ? FontWeight.w400
                    : (isBody ? fontTheme.fontWeight : FontWeight.w500),
                color: segment.isAside ? asideColor : speechColor,
              ),
            ),
          )
          .toList(),
    );

    // Preserve literal Markdown and keep code outside content-font decoration.
    final code = RegExp(r'(```|~~~)[\s\S]*?(?:\1|$)|(`+)[^\n]*?\2');
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in code.allMatches(message.content)) {
      if (match.start > cursor) {
        spans.add(plain(message.content.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(0),
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 16,
            height: 1.42,
            fontWeight: FontWeight.w400,
            color: speechColor,
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < message.content.length) {
      spans.add(plain(message.content.substring(cursor)));
    }
    return Text.rich(TextSpan(children: spans));
  }
}
