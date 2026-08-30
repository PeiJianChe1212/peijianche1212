/// 聊天模型输出的统一最后防线。
///
/// Prompt 负责表达风格；这里仅做高置信度的格式清理，不改写角色台词。
class ChatReplySanitizer {
  const ChatReplySanitizer._();

  static String clean(String value) {
    final output = <String>[];
    for (final rawLine in value.replaceAll('\r\n', '\n').split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (_internalFence.hasMatch(line) ||
          _standaloneSystemMarker.hasMatch(line)) {
        continue;
      }
      final bubbles = line.split(_segmentSeparator);
      final cleanedBubbles = <String>[];
      for (final bubble in bubbles) {
        final withoutLabel = bubble.replaceFirst(
          RegExp(r'^\s*消息\s*\d+\s*[:：]\s*'),
          '',
        );
        final cleaned = _removeBoundaryOrphanQuotes(
          _removeNarrationStructure(withoutLabel),
        );
        if (cleaned.isNotEmpty) cleanedBubbles.add(cleaned);
      }
      if (cleanedBubbles.isNotEmpty) {
        output.add(cleanedBubbles.join(_segmentSeparator));
      }
    }
    return output.join('\n').trim();
  }

  static final RegExp _internalFence = RegExp(
    r'^```(?:json|text|markdown)?\s*$',
    caseSensitive: false,
  );
  static final RegExp _standaloneSystemMarker = RegExp(
    r'^(?:</?system>|\[/?system\]|【系统(?:提示|消息|规则)】)$',
    caseSensitive: false,
  );

  static bool containsNarrationStructure(String value) => value
      .replaceAll('\r\n', '\n')
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .expand((line) => line.split(_segmentSeparator))
      .any((line) => _removeNarrationStructure(line) != line.trim());

  static String _removeNarrationStructure(String value) {
    var output = value.trim();
    while (true) {
      final match = _leadingStageDirection.firstMatch(output);
      if (match == null) break;
      final direction = [
        for (var index = 1; index <= 5; index++) match.group(index),
      ].whereType<String>().join();
      if (!_actionCue.hasMatch(direction)) break;
      output = output.substring(match.end).trimLeft();
    }

    final bareNarration = _leadingBareNarration.firstMatch(output);
    if (bareNarration != null) {
      output = output.substring(bareNarration.end).trimLeft();
    }

    final colon = _narrationColon.firstMatch(output);
    if (colon != null) {
      final prefix = colon.group(1) ?? '';
      if (_actionCue.hasMatch(prefix)) {
        output = output.substring(colon.end).trimLeft();
      }
    }
    return output.trim();
  }

  static String _removeBoundaryOrphanQuotes(String value) {
    var output = value.trim();
    for (final pair in _quotePairs) {
      final openCount = pair.$1.allMatches(output).length;
      final closeCount = pair.$2.allMatches(output).length;
      if (openCount > 0 && closeCount == 0) {
        output = output.replaceFirst(pair.$3, '').trimLeft();
      } else if (closeCount > 0 && openCount == 0) {
        output = output.replaceFirst(pair.$4, '').trimRight();
      }
    }
    if (_straightDoubleQuote.allMatches(output).length.isOdd) {
      output = output
          .replaceFirst(_straightDoubleQuoteAtStart, '')
          .replaceFirst(_straightDoubleQuoteAtEnd, '')
          .trim();
    }
    return output;
  }

  static final RegExp _leadingStageDirection = RegExp(
    r'^(?:（([^（）]{1,30})）|\(([^()]{1,30})\)|【([^【】]{1,30})】|\[([^\[\]]{1,30})\]|\*([^*]{1,30})\*)\s*',
  );
  static final RegExp _narrationColon = RegExp(r'^([^\n：:]{1,36})[：:]\s*');
  static final RegExp _leadingBareNarration = RegExp(
    r'^[“"「『‘]?(?:(?:他|她)\s*)?(?:顿了(?:一下|一会儿|片刻)|停顿了(?:一下|片刻))[，,]\s*',
  );
  static final RegExp _actionCue = RegExp(
    r'笑|smiles?|叹气|叹了口气|顿了顿|顿了一下|停顿|沉默|挑眉|皱眉|眉心|嘴角|眼神|目光|表情|神色|语气|声音|声线|尾音|压低|放轻|放软|揉|摸|拍|抬手|点头|摇头|转身|靠近|俯身|看了|看着|扫眼|盯着|眯|闭眼|呼吸|勾唇|扬起|指尖|手撑|转着|开心|难过|生气',
    caseSensitive: false,
  );
  static final List<(RegExp, RegExp, RegExp, RegExp)> _quotePairs = [
    (RegExp(r'“'), RegExp(r'”'), RegExp(r'^“\s*'), RegExp(r'\s*”$')),
    (RegExp(r'「'), RegExp(r'」'), RegExp(r'^「\s*'), RegExp(r'\s*」$')),
    (RegExp(r'『'), RegExp(r'』'), RegExp(r'^『\s*'), RegExp(r'\s*』$')),
    (RegExp(r'《'), RegExp(r'》'), RegExp(r'^《\s*'), RegExp(r'\s*》$')),
    (RegExp(r'〈'), RegExp(r'〉'), RegExp(r'^〈\s*'), RegExp(r'\s*〉$')),
    (RegExp(r'‘'), RegExp(r'’'), RegExp(r'^‘\s*'), RegExp(r'\s*’$')),
  ];
  static final RegExp _straightDoubleQuote = RegExp('"');
  static final RegExp _straightDoubleQuoteAtStart = RegExp(r'^"\s*');
  static final RegExp _straightDoubleQuoteAtEnd = RegExp(r'\s*"$');
  static const _segmentSeparator = '<|PEILINK_MSG|>';
}
