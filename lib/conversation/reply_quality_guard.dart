import 'chat_reply_sanitizer.dart';
import 'reply_segment_parser.dart';

enum ReplyQualityIssue {
  empty,
  internalFormatLeak,
  assistantTemplate,
  consecutiveQuestions,
  repeated,
  tooLong,
  novelNarration,
}

class ReplyQualityResult {
  const ReplyQualityResult({
    required this.segments,
    required this.issues,
    required this.shouldRetry,
  });

  final List<String> segments;
  final Set<ReplyQualityIssue> issues;
  final bool shouldRetry;
  String get output => segments.join(ReplySegmentParser.separator);
}

class ReplyQualityGuard {
  const ReplyQualityGuard();

  ReplyQualityResult inspect({
    required String reply,
    List<String> recentAssistantReplies = const [],
    bool allowRetry = true,
  }) {
    final issues = <ReplyQualityIssue>{};
    final raw = reply.trim();
    if (raw.isEmpty) issues.add(ReplyQualityIssue.empty);
    if (_internalLeak.hasMatch(raw)) {
      issues.add(ReplyQualityIssue.internalFormatLeak);
    }
    if (_assistantTemplate.hasMatch(raw)) {
      issues.add(ReplyQualityIssue.assistantTemplate);
    }
    if (raw.length > 1600) issues.add(ReplyQualityIssue.tooLong);
    if (ChatReplySanitizer.containsNarrationStructure(raw)) {
      issues.add(ReplyQualityIssue.novelNarration);
    }

    var sanitized = ChatReplySanitizer.clean(
      raw,
    ).replaceAll(RegExp(r'^\s*消息\s*\d+\s*[:：]\s*', multiLine: true), '').trim();
    if (_unsafeStructuredLeak.hasMatch(sanitized)) sanitized = '';
    var segments = ReplySegmentParser.parse(sanitized)
        .where((segment) => !segment.contains(ReplySegmentParser.separator))
        .toList();
    if (segments.length >= 2 && segments.every(_endsWithQuestion)) {
      issues.add(ReplyQualityIssue.consecutiveQuestions);
    }

    final recent = recentAssistantReplies.where(
      (item) => item.trim().isNotEmpty,
    );
    final kept = <String>[];
    for (final segment in segments) {
      final duplicate = recent.any((previous) => _similar(segment, previous));
      if (duplicate) {
        issues.add(ReplyQualityIssue.repeated);
      } else {
        kept.add(segment);
      }
    }
    segments = kept;
    if (segments.isEmpty && raw.isNotEmpty) {
      issues.add(ReplyQualityIssue.repeated);
    }

    final hardFailure =
        segments.isEmpty ||
        issues.contains(ReplyQualityIssue.internalFormatLeak) ||
        issues.contains(ReplyQualityIssue.assistantTemplate) ||
        issues.contains(ReplyQualityIssue.tooLong);
    return ReplyQualityResult(
      segments: segments,
      issues: issues,
      shouldRetry: allowRetry && hardFailure,
    );
  }

  static bool _endsWithQuestion(String value) =>
      RegExp(r'[？?][”」』】）)]?[。.!！]*$').hasMatch(value.trim());

  static bool _similar(String first, String second) {
    final a = _normalize(first);
    final b = _normalize(second);
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    final shorter = a.length < b.length ? a : b;
    final longer = a.length < b.length ? b : a;
    if (shorter.length >= 8 && longer.contains(shorter)) return true;
    final left = _bigrams(a);
    final right = _bigrams(b);
    final union = left.union(right).length;
    return union > 0 && left.intersection(right).length / union >= .68;
  }

  static String _normalize(String value) => value.toLowerCase().replaceAll(
    RegExp(r'''[\s，。！？、,.!?~～“”"'（）()【】\[\]*…]'''),
    '',
  );

  static Set<String> _bigrams(String value) {
    if (value.length < 2) return {value};
    return {
      for (var index = 0; index < value.length - 1; index++)
        value.substring(index, index + 2),
    };
  }

  static final _internalLeak = RegExp(
    r'```|(?:^|\n)\s*消息\s*\d+\s*[:：]|</?system>|\[/?system\]|"role"\s*:\s*"system"|system_prompt',
    multiLine: true,
    caseSensitive: false,
  );
  static final _unsafeStructuredLeak = RegExp(
    r'</?system>|\[/?system\]|"role"\s*:\s*"system"|system_prompt',
    caseSensitive: false,
  );
  static final _assistantTemplate = RegExp(
    r'有什么我可以帮你的吗|今天怎么样|最近有什么(?:有趣|好玩)的事|想聊点什么|有什么想(?:和我)?分享的吗|需要我陪你聊聊吗|想我哪一点|是不是觉得我很帅',
  );
}

class ReplyQualityRetryRunner {
  const ReplyQualityRetryRunner({this.guard = const ReplyQualityGuard()});
  final ReplyQualityGuard guard;

  Future<String> run({
    required Future<String> Function(int attempt) generate,
    List<String> recentAssistantReplies = const [],
  }) async {
    var raw = await generate(0);
    var result = guard.inspect(
      reply: raw,
      recentAssistantReplies: recentAssistantReplies,
    );
    if (!result.shouldRetry) return result.output;

    raw = await generate(1);
    result = guard.inspect(
      reply: raw,
      recentAssistantReplies: recentAssistantReplies,
      allowRetry: false,
    );
    return result.output.trim().isNotEmpty ? result.output : '……';
  }
}
