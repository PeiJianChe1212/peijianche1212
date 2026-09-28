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
      // Every complete quoted span of the whole reply is considered in original
      // order, and the text between quotes is judged separately. Gap text is
      // never spoken: only quotations that sit between structural boundaries
      // (actions, punctuation, narration colon) are promoted to speech.
      final stripped = _stripLeadingActionBlocks(source);
      if (stripped.unbalanced) notes.add('unbalanced_leading_action');
      if (stripped.removed) notes.add('leading_action_removed');
      final spans = _quotedSpans(source);
      // A quotation inside a stage direction is not spoken dialogue: it must
      // not become a span, and it must not split the surrounding action block
      // into a fake introducer for the next real utterance.
      final actionMask = _actionRegionMask(source);
      final dialogueSpans = spans
          .where((span) => !actionMask[span.start])
          .toList(growable: false);
      if (dialogueSpans.isNotEmpty) {
        final gaps = _gapsBetweenQuotes(source, dialogueSpans);
        for (var index = 0; index < dialogueSpans.length; index++) {
          final content = dialogueSpans[index].content.trim();
          if (content.isEmpty || _isStandaloneNarration(content)) {
            continue;
          }
          // Gap roles are distinct. The gap before a quotation introduces it
          // (structural glue or a narration clause that names speech). The gap
          // between two quotations belongs to the *next* quotation, so it must
          // never drop the preceding one. Only the trailing gap still has to be
          // a boundary, which keeps sentence-glued quotations unspoken.
          if (!_gapIntroducesSpeech(gaps[index])) continue;
          if (index == dialogueSpans.length - 1 &&
              !_gapIsStructural(gaps[index + 1])) {
            continue;
          }
          output.add(content);
        }
        if (output.isEmpty) {
          notes.add('unsafe_quoted_dialogue');
        } else {
          notes.add('quote_extracted');
        }
      } else if (_startsWithQuoteOpener(stripped.text)) {
        // A dangling opening quote is ambiguous: never guess or promote text.
        notes.add('unbalanced_quote');
      } else if (stripped.text.isNotEmpty) {
        // No quoted dialogue: normal prose. A complete parenthesised block that
        // stands as its own sentence is a stage direction and is dropped;
        // parentheticals inside a sentence stay verbatim.
        final prose = _stripStandaloneActionRegions(stripped.text, notes);
        final adapted = fromCoreReplyDetailed(
          prose,
          restoreEmptyResult: false,
        );
        output.add(adapted.text);
        notes.add(adapted.note);
      }
    }
    return result(_joinNatural(output));
  }

  /// Removes the parenthesised action blocks that may introduce the reply.
  static ({String text, bool removed, bool unbalanced})
  _stripLeadingActionBlocks(String value) {
    var text = value;
    var removed = false;
    while (text.startsWith('（') || text.startsWith('(')) {
      final end = _leadingParenthesisEnd(text);
      if (end == null) {
        return (text: '', removed: removed, unbalanced: true);
      }
      removed = true;
      text = text.substring(end).trimLeft();
    }
    return (text: text, removed: removed, unbalanced: false);
  }

  /// Text before/between/after the quoted spans, in original order.
  static List<String> _gapsBetweenQuotes(
    String source,
    List<_QuoteSpan> spans,
  ) {
    final gaps = <String>[];
    var cursor = 0;
    for (final span in spans) {
      gaps.add(source.substring(cursor, span.start));
      cursor = span.end;
    }
    gaps.add(source.substring(cursor));
    return gaps;
  }

  /// True when [gap] is structural glue that may sit next to a spoken quote:
  /// empty text, parenthesised or cued action blocks, punctuation only,
  /// standalone narration, a narration colon introducer, or a clause that has
  /// already terminated. The gap itself is never read aloud.
  static bool _gapIsStructural(String gap) {
    var rest = gap.trim();
    if (rest.isEmpty) return true;
    while (rest.startsWith('（') || rest.startsWith('(')) {
      final end = _leadingParenthesisEnd(rest);
      if (end == null) return false;
      rest = rest.substring(end).trimLeft();
    }
    if (rest.isEmpty) return true;
    final withoutActions = _removeActionBlocks(rest).trim();
    if (withoutActions.isEmpty) return true;
    if (_onlyPunctuation.hasMatch(withoutActions)) return true;
    if (_standaloneNarration.hasMatch(withoutActions)) return true;
    if (_narrationColonPrefix.hasMatch(withoutActions)) return true;
    return _clauseBoundaryEnd.hasMatch(withoutActions);
  }

  /// True when [gap] reads as the introduction of the quotation that follows
  /// it: structural glue, or a narration clause that names speech even when it
  /// happens to carry no closing punctuation.
  static bool _gapIntroducesSpeech(String gap) =>
      _gapIsStructural(gap) || _gapHasSpeechCue(gap);

  static bool _gapHasSpeechCue(String gap) {
    final withoutActions = _removeActionBlocks(gap.trim());
    if (withoutActions.trim().isEmpty) return false;
    // Descriptive verbs introduce a quoted term, not spoken dialogue
    // (e.g. 他念出“蜜雪冰城”三个字), so they never open a speech span.
    if (_quotedTermOnly.hasMatch(withoutActions)) return false;
    return _speechCue.hasMatch(withoutActions);
  }

  /// Balanced stage-direction regions (parentheses, brackets, asterisks) in
  /// source order. Unbalanced openers are ignored, which keeps the existing
  /// conservative behaviour.
  static List<(int, int)> _actionRegions(String source) {
    final regions = <(int, int)>[];
    for (final pair in _actionRegionPairs) {
      _collectActionRegions(source, pair.$1, pair.$2, regions);
    }
    regions.sort((left, right) => left.$1.compareTo(right.$1));
    return regions;
  }

  static void _collectActionRegions(
    String source,
    String open,
    String close,
    List<(int, int)> regions,
  ) {
    if (open == close) {
      var cursor = 0;
      while (cursor < source.length) {
        final start = source.indexOf(open, cursor);
        if (start < 0) return;
        final end = source.indexOf(close, start + open.length);
        if (end < 0) return;
        regions.add((start, end + close.length));
        cursor = end + close.length;
      }
      return;
    }
    final stack = <int>[];
    for (var index = 0; index < source.length; index++) {
      if (source.startsWith(open, index)) {
        stack.add(index);
        index += open.length - 1;
        continue;
      }
      if (source.startsWith(close, index) && stack.isNotEmpty) {
        final start = stack.removeLast();
        if (stack.isEmpty) {
          regions.add((start, index + close.length));
        }
        index += close.length - 1;
      }
    }
  }

  /// Marks every code unit inside a balanced stage-direction region.
  static List<bool> _actionRegionMask(String source) {
    final mask = List<bool>.filled(source.length, false);
    for (final region in _actionRegions(source)) {
      for (var index = region.$1; index < region.$2; index++) {
        mask[index] = true;
      }
    }
    return mask;
  }

  /// Removes stage-direction regions that stand as their own sentence: the
  /// character before the block is a sentence boundary or the text begins
  /// there. Embedded parentheticals such as `我明天（周三）来。` are kept.
  static String _stripStandaloneActionRegions(
    String text,
    List<String> notes,
  ) {
    final regions = _actionRegions(text);
    if (regions.isEmpty) return text;
    final buffer = StringBuffer();
    var cursor = 0;
    var removed = false;
    for (final region in regions) {
      if (region.$1 < cursor) continue;
      if (!_isStandaloneActionRegion(text, region.$1)) continue;
      buffer.write(text.substring(cursor, region.$1));
      cursor = region.$2;
      removed = true;
    }
    if (!removed) return text;
    buffer.write(text.substring(cursor));
    notes.add('standalone_action_block_removed');
    return buffer.toString();
  }

  static bool _isStandaloneActionRegion(String text, int start) {
    var index = start - 1;
    while (index >= 0 && (text[index] == ' ' || text[index] == '\t')) {
      index--;
    }
    if (index < 0) return true;
    return _sentenceBoundaryBefore.contains(text[index]);
  }

  static const _sentenceBoundaryBefore = '。！？!?…；;\n\r';

  static bool _startsWithQuoteOpener(String value) {
    final text = value.trimLeft();
    for (final pair in _QuoteScanner._pairs) {
      if (text.startsWith(pair.$1)) return true;
    }
    return false;
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

  /// A clause that has already terminated (or a dialogue colon) directly before
  /// or after a quotation boundary.
  static final RegExp _clauseBoundaryEnd = RegExp(r'[，,。！？!?、；;：:…]$');

  /// Narration that names speech without necessarily ending in punctuation.
  static final RegExp _speechCue = RegExp(
    r'补(?:了)?(?:一)?句|接(?:着)?(?:说|道)?|继续(?:说|道)?|开口|说|道|问|答|嘟囔|嘟哝|喊|叫',
  );

  /// Descriptive quotation markers: they introduce a quoted term, not dialogue.
  static final RegExp _quotedTermOnly = RegExp(
    r'念出|念着|写着|写的是|写下|标注|署名|标题',
  );

  /// Balanced stage-direction regions that are never spoken dialogue.
  static const _actionRegionPairs = <(String, String)>[
    ('（', '）'),
    ('(', ')'),
    ('【', '】'),
    ('[', ']'),
    ('*', '*'),
  ];

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
