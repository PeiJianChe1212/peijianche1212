import '../conversation/chat_reply_sanitizer.dart';
import '../conversation/reply_segment_parser.dart';

abstract final class PhysicalSpeechTextAdapter {
  /// Contract-failure path: remove structural prefixes before sentence parsing.
  /// Never restore an empty result to the original source.
  static PhysicalSpeechFilterResult speechSafeFallback(String reply) {
    final notes = <String>['speech_safe_fallback'];
    PhysicalSpeechFilterResult result(String text) =>
        PhysicalSpeechFilterResult(
          text: text,
          fallbackUsed: true,
          note: [...notes, if (text.isEmpty) 'empty_safe_result'].join(';'),
        );
    // A malformed contract without a usable DISPLAY is ambiguous. Do not speak
    // its tags or guess which duplicate/incomplete block was intended.
    if (RegExp(
      r'PEILINK_(?:DISPLAY|SPOKEN)',
      caseSensitive: false,
    ).hasMatch(reply)) {
      notes.add('ambiguous_contract_markup');
      return result('');
    }
    var source = reply.trim();
    if (source.startsWith('```')) {
      final newline = source.indexOf('\n');
      if (newline < 0 || !source.endsWith('```')) return result('');
      source = source.substring(newline + 1, source.length - 3).trim();
    }
    final output = <String>[];
    {
      var line = source;
      final quoted = <String>[];
      while (line.isNotEmpty) {
        if (line.startsWith('（') || line.startsWith('(')) {
          final end = _leadingParenthesisEnd(line);
          if (end == null) {
            notes.add('unbalanced_leading_action');
            line = '';
            break;
          }
          notes.add('leading_action_removed');
          line = line.substring(end).trimLeft();
          continue;
        }
        final close = line.startsWith('“')
            ? '”'
            : line.startsWith('"')
            ? '"'
            : null;
        if (close == null) break;
        final end = line.indexOf(close, 1);
        if (end < 0) {
          notes.add('unbalanced_quote');
          line = '';
          break;
        }
        quoted.add(line.substring(1, end).trim());
        notes.add('quote_extracted');
        line = line.substring(end + 1).trimLeft();
      }
      if (quoted.isNotEmpty) {
        // Once a quoted utterance is identified, unquoted trailing narration
        // is not promoted to speech. Parentheses inside dialogue remain intact.
        output.addAll(quoted.where((text) => text.isNotEmpty));
      } else if (line.isNotEmpty) {
        final adapted = fromCoreReplyDetailed(line, restoreEmptyResult: false);
        output.add(adapted.text);
        notes.add(adapted.note);
      }
    }
    return result(_joinNatural(output));
  }

  static int? _leadingParenthesisEnd(String value) {
    final stack = <String>[];
    for (var i = 0; i < value.length; i++) {
      final char = value[i];
      if (char == '(' || char == '（') {
        stack.add(char == '(' ? ')' : '）');
      } else if (char == ')' || char == '）') {
        if (stack.isEmpty || stack.removeLast() != char) return null;
        if (stack.isEmpty) return i + 1;
      }
    }
    return null;
  }

  /// Backwards-compatible string entry used by existing staged code and tests.
  static String fromCoreReply(String reply) =>
      fromCoreReplyDetailed(reply).text;

  /// Physical-only spoken text conversion.
  ///
  /// This never rewrites [reply] and never affects normal chat display,
  /// Core Bridge, or persisted role history. It only decides what should be
  /// read aloud.
  static PhysicalSpeechFilterResult fromCoreReplyDetailed(
    String reply, {
    bool restoreEmptyResult = true,
  }) {
    final cleaned = ChatReplySanitizer.clean(reply);
    final segments = ReplySegmentParser.parse(cleaned);
    if (segments.isEmpty) {
      if (!restoreEmptyResult) {
        return const PhysicalSpeechFilterResult(
          text: '',
          fallbackUsed: false,
          note: 'empty_safe_result',
        );
      }
      throw const FormatException('AI 回复没有可朗读内容');
    }

    final notes = <String>[];
    final output = <String>[];
    for (final segment in segments) {
      final quoted = _tryExtractQuotedDialogue(segment);
      if (quoted != null) {
        if (quoted.isEmpty) continue;
        output.addAll(quoted);
        notes.add('quoted_dialogue_extracted');
        continue;
      }

      final withoutActions = _removeActionBlocks(segment);
      if (withoutActions != segment) {
        notes.add('action_block_removed');
      }
      final candidate = withoutActions.trim();
      if (candidate.isEmpty) continue;

      if (_isStandaloneNarration(candidate)) {
        notes.add('standalone_narration_removed');
        continue;
      }
      output.add(candidate);
    }

    final spoken = _joinNatural(output);
    if (spoken.isEmpty) {
      if (!restoreEmptyResult) {
        return PhysicalSpeechFilterResult(
          text: '',
          fallbackUsed: false,
          note: ['empty_safe_result', ...notes].join(';'),
        );
      }
      if (cleaned.trim().isEmpty) {
        throw const FormatException('AI 回复没有可朗读内容');
      }
      return PhysicalSpeechFilterResult(
        text: segments.join('\n'),
        fallbackUsed: true,
        note: notes.isEmpty
            ? 'fallback_after_empty_filter'
            : 'fallback_after_empty_filter;${notes.join(';')}',
      );
    }

    return PhysicalSpeechFilterResult(
      text: spoken,
      fallbackUsed: false,
      note: notes.isEmpty ? 'no_filter' : notes.join(';'),
    );
  }

  static String _joinNatural(List<String> segments) {
    final result = <String>[];
    for (final segment in segments) {
      final value = segment.trim();
      if (value.isNotEmpty) result.add(value);
    }
    return result.join('\n');
  }

  /// Tries to turn a segment containing complete quoted dialogue into spoken
  /// dialogue only. Returns null when the structure is not high-confidence.
  static List<String>? _tryExtractQuotedDialogue(String value) {
    final spans = _quotedSpans(value);
    if (spans.isEmpty) return null;
    if (spans.any((span) => span.content.trim().isEmpty)) return null;
    if (!_outsideQuotesIsRemovable(value, spans)) return null;
    return spans.map((span) => span.content.trim()).toList(growable: false);
  }

  static List<_QuoteSpan> _quotedSpans(String value) {
    final result = <_QuoteSpan>[];
    final scan = _QuoteScanner(value);
    while (true) {
      final span = scan.next();
      if (span == null) break;
      result.add(span);
    }
    return result;
  }

  static bool _outsideQuotesIsRemovable(String value, List<_QuoteSpan> spans) {
    var outside = value;
    for (final span in spans.reversed) {
      outside = outside.substring(0, span.start) + outside.substring(span.end);
    }
    outside = outside.trim();
    if (outside.isEmpty) return true;
    if (_standaloneNarration.hasMatch(outside)) return true;
    if (_narrationColonPrefix.hasMatch(outside)) return true;
    if (_onlyPunctuation.hasMatch(outside)) return true;
    return false;
  }

  static String _removeActionBlocks(String value) {
    var output = value;
    var searchStart = 0;
    while (true) {
      final searchable = output.substring(searchStart);
      final match = _actionBlockPattern.firstMatch(searchable);
      if (match == null) break;
      final content = [
        for (var i = 1; i <= 5; i++) match.group(i),
      ].whereType<String>().join().trim();
      if (content.isEmpty ||
          content.length > 80 ||
          !_actionBlockCue.hasMatch(content)) {
        searchStart = searchStart + match.end;
        continue;
      }
      final absoluteStart = searchStart + match.start;
      final absoluteEnd = searchStart + match.end;
      output = output.replaceRange(absoluteStart, absoluteEnd, '');
      searchStart = absoluteStart;
    }
    return output
        .replaceAll(RegExp(r'([。！？，、：；])\s+'), r'$1')
        .replaceAll(RegExp(r'\s+([。！？，、：；])'), r'$1')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  static bool _isStandaloneNarration(String value) =>
      _standaloneNarration.hasMatch(value.trim());

  static final RegExp _standaloneNarration = RegExp(
    r'^[他她]?(?:停顿了?[^。！？]{0,24}|'
    r'尾音[^。！？]{0,24}(?:上扬|压低|放轻)|'
    r'(?:声音|语气)[^。！？]{0,16}(?:放轻|压低|放缓)|'
    r'(?:往后)?靠(?:进|在)?椅背[^。！？]{0,32}|'
    r'手指[^。！？]{0,32}(?:敲|点)[^。！？]{0,24}|'
    r'像是[^。！？]{0,12}(?:认真|正在|仔细)考虑)[。！？…]*$',
  );

  static final RegExp _narrationColonPrefix = RegExp(
    r'^[他她]?[^：:]{0,40}?'
    r'(?:停顿|顿了顿|尾音|声音|语气|放轻|压低|上扬|神色|目光|嘴角|'
    r'靠进椅背|手指|敲|开口|说|道)[：:]$',
  );

  static final RegExp _onlyPunctuation = RegExp(r'^[\s，。！？、：:；;…\-—~～]+$');

  static final RegExp _actionBlockPattern = RegExp(
    r'（([^（）]{1,80})）|\(([^()]{1,80})\)|'
    r'\*([^*]{1,80})\*|【([^【】]{1,80})】|\[([^\[\]]{1,80})\]',
  );

  static final RegExp _actionBlockCue = RegExp(
    r'^(?:被[^，。！？]{1,14}逗笑|'
    r'(?:低|轻|微|哼)?笑|'
    r'叹气|叹息|'
    r'顿(?:了|住|一下|片刻)|'
    r'沉默|挑眉|皱眉|抬眼|垂眼|闭眼|眯眼|'
    r'摇头|点头|抬头|低头|'
    r'抬手|放下|伸手|收回|'
    r'敲(?:了|了?一下)|'
    r'靠(?:进|在)椅背|'
    r'扫?了一眼|看了看|看着|盯着|'
    r'尾音|语气|声音|声线|神色|目光|眼神|表情|嘴角|指尖|'
    r'开心|难过|生气|'
    r'整理|翻开|'
    r'顿住|顿了顿)',
  );
}

class PhysicalSpeechFilterResult {
  const PhysicalSpeechFilterResult({
    required this.text,
    required this.fallbackUsed,
    required this.note,
  });

  final String text;
  final bool fallbackUsed;
  final String note;
}

class _QuoteSpan {
  const _QuoteSpan({
    required this.content,
    required this.start,
    required this.end,
  });

  final String content;
  final int start;
  final int end;
}

class _QuoteScanner {
  _QuoteScanner(this.value);

  final String value;
  int cursor = 0;

  static const _pairs = <(String, String)>[
    ('“', '”'),
    ('『', '』'),
    ('「', '」'),
    ('‘', '’'),
    ('"', '"'),
  ];

  _QuoteSpan? next() {
    while (cursor < value.length) {
      for (final pair in _pairs) {
        final open = pair.$1;
        if (!value.startsWith(open, cursor)) continue;
        final contentStart = cursor + open.length;
        final close = value.indexOf(pair.$2, contentStart);
        if (close < 0) {
          cursor = contentStart;
          continue;
        }
        final span = _QuoteSpan(
          content: value.substring(contentStart, close),
          start: cursor,
          end: close + pair.$2.length,
        );
        cursor = close + pair.$2.length;
        return span;
      }
      cursor++;
    }
    return null;
  }
}
