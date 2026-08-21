import 'dart:convert';

class StructuredModelOutputException implements Exception {
  const StructuredModelOutputException({required this.stage, this.cause});

  final String stage;
  final Object? cause;

  @override
  String toString() => '$stage 返回了无法解析的结构化结果。';
}

dynamic decodeStructuredModelJson(String value, {required String stage}) {
  try {
    return jsonDecode(value);
  } on FormatException catch (error) {
    throw StructuredModelOutputException(stage: stage, cause: error);
  }
}
