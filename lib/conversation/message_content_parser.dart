/// 一段消息里，被分开的“说出口的话”或“括号说明”。
class MessageContentSegment {
  const MessageContentSegment({
    required this.text,
    required this.isAside,
  });

  final String text;

  /// true 表示括号里的说明，不属于角色真正说出口的话。
  final bool isAside;
}

/// 把一条消息分成“真正说出口的话”和“括号里的说明”。
///
/// 支持中文全角括号 `（ ）` 和英文半角括号 `( )`，也支持一条消息中
/// 出现多段括号内容。没有完整闭合的括号会保留为普通正文，避免误判。
class MessageContentParser {
  const MessageContentParser._();

  static List<MessageContentSegment> parse(String content) {
    if (content.isEmpty) return const [];

    final segments = <MessageContentSegment>[];
    final normalBuffer = StringBuffer();
    final asideBuffer = StringBuffer();

    String? openingBracket;
    String? closingBracket;
    var depth = 0;

    void addNormal() {
      if (normalBuffer.isEmpty) return;
      segments.add(
        MessageContentSegment(
          text: normalBuffer.toString(),
          isAside: false,
        ),
      );
      normalBuffer.clear();
    }

    void addAside() {
      if (asideBuffer.isEmpty) return;
      segments.add(
        MessageContentSegment(
          text: asideBuffer.toString(),
          isAside: true,
        ),
      );
      asideBuffer.clear();
    }

    for (var index = 0; index < content.length; index++) {
      final character = content[index];

      if (depth == 0) {
        if (character == '（' || character == '(') {
          addNormal();
          openingBracket = character;
          closingBracket = character == '（' ? '）' : ')';
          depth = 1;
          asideBuffer.write(character);
        } else {
          normalBuffer.write(character);
        }
        continue;
      }

      asideBuffer.write(character);

      if (character == openingBracket) {
        depth++;
      } else if (character == closingBracket) {
        depth--;
        if (depth == 0) {
          addAside();
          openingBracket = null;
          closingBracket = null;
        }
      }
    }

    // 括号没有闭合时，不把它当成说明，原样并回普通正文。
    if (asideBuffer.isNotEmpty) {
      normalBuffer.write(asideBuffer.toString());
    }
    addNormal();

    return segments;
  }

  /// 留给以后语音使用：只取真正需要被角色读出来的内容。
  static String spokenText(String content) {
    return parse(content)
        .where((segment) => !segment.isAside)
        .map((segment) => segment.text)
        .join()
        .trim();
  }
}
