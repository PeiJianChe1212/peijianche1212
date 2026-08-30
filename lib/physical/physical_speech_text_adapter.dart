import '../conversation/chat_reply_sanitizer.dart';
import '../conversation/reply_segment_parser.dart';

abstract final class PhysicalSpeechTextAdapter {
  static String fromCoreReply(String reply) {
    final cleaned = ChatReplySanitizer.clean(reply);
    final segments = ReplySegmentParser.parse(cleaned);
    if (segments.isEmpty) throw const FormatException('AI 回复没有可朗读内容');
    return segments.join('\n');
  }
}
