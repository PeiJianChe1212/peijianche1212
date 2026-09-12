class EchoTextSanitizer {
  const EchoTextSanitizer._();

  /// Removes stage directions only at the beginning or on a line by itself.
  /// Parentheses used normally inside prose are retained.
  static String clean(String value) {
    var result = value.trim();
    final block = RegExp(r'^\s*[（(]([^）)\r\n]{1,160})[）)]\s*');
    while (true) {
      final match = block.firstMatch(result);
      if (match == null || !_looksLikeAction(match.group(1) ?? '')) break;
      result = result.substring(match.end).trimLeft();
    }
    return result
        .split('\n')
        .where((line) {
          final match = RegExp(
            r'^\s*[（(]([^）)]{1,160})[）)]\s*$',
          ).firstMatch(line);
          return match == null || !_looksLikeAction(match.group(1) ?? '');
        })
        .join('\n')
        .trim();
  }

  static bool _looksLikeAction(String value) => RegExp(
    r'指尖|手指|抬手|低头|抬眼|眨眼|挑眉|耸肩|转着|转动|拿起|放下|靠着|倚着|笑|叹|沉默|轻轻|缓缓|悄悄',
  ).hasMatch(value);
}
