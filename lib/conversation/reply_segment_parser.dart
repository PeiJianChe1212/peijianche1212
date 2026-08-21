import 'dart:convert';

class ReplySegmentParser {
  const ReplySegmentParser._();

  static const separator = '<|PEILINK_MSG|>';

  static List<String> parse(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return const [];

    final jsonSegments = _parseJson(clean);
    if (jsonSegments.length > 1) return _normalize(jsonSegments);

    if (clean.contains(separator)) {
      return _normalize(clean.split(separator));
    }

    final paragraphs = clean.split(RegExp(r'\n\s*\n|\n+'));
    if (paragraphs.length > 1) return _normalize(paragraphs);

    // 模型偶尔会忽略分隔符。仅在一条回复确实包含多个完整信息句时兜底拆分，
    // 简短回应、玩笑和口语碎片保持单气泡。
    if (clean.length >= 24) {
      final sentences = RegExp(r'[^。！？!?…]+[。！？!?…]+|[^。！？!?…]+$')
          .allMatches(clean)
          .map((match) => match.group(0)?.trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList();
      if (sentences.length >= 2 && sentences.length <= 6) {
        return _normalize(_mergeTiny(sentences));
      }
    }
    return [clean];
  }

  static List<String> _parseJson(String value) {
    if (!value.startsWith('[') || !value.endsWith(']')) return const [];
    try {
      final decoded = jsonDecode(value);
      if (decoded is List) {
        return decoded.map((item) => item.toString()).toList();
      }
    } catch (_) {}
    return const [];
  }

  static List<String> _mergeTiny(List<String> values) {
    final result = <String>[];
    for (final value in values) {
      if (value.length < 4 && result.isNotEmpty) {
        result[result.length - 1] = '${result.last}$value';
      } else {
        result.add(value);
      }
    }
    return result;
  }

  static List<String> _normalize(Iterable<String> values) => values
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .take(8)
      .toList(growable: false);
}
