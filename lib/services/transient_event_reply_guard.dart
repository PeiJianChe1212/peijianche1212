typedef EventCompletion =
    Future<String> Function(List<Map<String, dynamic>> messages);

class TransientEventReplyGuard {
  const TransientEventReplyGuard._();

  static const redPacketUserTurn =
      '[Red packet event]\nI sent you a red packet. You have received it. '
      'Please respond naturally in character. Do not mention or guess the amount.';

  static List<Map<String, dynamic>> appendUserTurn(
    List<Map<String, dynamic>> messages,
  ) {
    return [
      ...messages.map((message) => Map<String, dynamic>.from(message)),
      const {'role': 'user', 'content': redPacketUserTurn},
    ];
  }

  static Future<String> completeWithEmptyReplyFallback({
    required List<Map<String, dynamic>> messages,
    required EventCompletion complete,
    String Function()? localFallback,
  }) async {
    final eventMessages = appendUserTurn(messages);
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final reply = (await complete(eventMessages)).trim();
        if (reply.isNotEmpty) return reply;
      } on FormatException catch (error) {
        if (!_isEmptyReply(error)) rethrow;
      }
    }
    return localFallback?.call().trim() ?? '';
  }

  static bool _isEmptyReply(FormatException error) {
    final message = error.message.toString();
    return message.contains('空回复') || message.contains('回复内容');
  }
}
