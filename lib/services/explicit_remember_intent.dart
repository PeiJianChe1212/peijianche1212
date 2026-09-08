import '../models/chat_message.dart';

/// Conservative, local command detection. No model call and no memory state.
class ExplicitRememberIntent {
  const ExplicitRememberIntent({required this.messageId, required this.target});

  final String messageId;
  final String target;

  static ExplicitRememberIntent? detect(ChatMessage message) {
    if (message.role != 'user' || !message.isVisibleInConversationContext) {
      return null;
    }
    final text = message.content.trim();
    if (RegExp(
      r'不用记|不必记|不要记|别记|无需记|开玩笑|逗你|提醒|还记得|记不记得|我记得|记住了吗|记住了没|要记住什么|如果|假如',
    ).hasMatch(text)) {
      return null;
    }
    // Quoted commands and reported speech do not authorize persistence.
    final direct = text.replaceAll(
      RegExp(r'''“[^”]*”|「[^」]*」|『[^』]*』|"[^"]*"|‘[^’]*’|'[^']*' '''.trim()),
      '',
    );
    if (RegExp(r'(他说|她说|别人说|有人说|引用|转述)').hasMatch(direct)) return null;
    final command = RegExp(
      r'(?:(?:你|请|务必|一定|要|得|必须|帮我|以后)\s*)+记住|^记住[：:，,]|以后记得|请记得|别忘了|不要忘(?:记)?|不能忘|这个.{0,4}(?:很|非常)重要|这件事.{0,6}(?:很|非常)重要',
    );
    if (!command.hasMatch(direct)) return null;
    return ExplicitRememberIntent(messageId: message.id, target: direct.trim());
  }

  /// Only a nearby user statement can resolve a deictic “remember this”.
  List<ChatMessage> window(List<ChatMessage> messages) {
    final index = messages.indexWhere((m) => m.id == messageId);
    if (index < 0) return const [];
    final current = messages[index];
    final deictic = RegExp(
      r'^(?:这个|这件事|这点|你|请|一定|务必|要|得|必须|帮我|记住|记得|别忘了|不要忘记|不能忘|对我|很重要|非常重要|[，。！？!?,.\s])+$',
    ).hasMatch(target);
    if (deictic) {
      for (var i = index - 1; i >= 0 && i >= index - 4; i--) {
        if (messages[i].role == 'user') return [messages[i], current];
      }
    }
    return [current];
  }

  static bool isChangeEvidence(String text) =>
      !RegExp(
        r'也喜欢|都喜欢|同时喜欢|开玩笑|不用记|不要记|如果|假如|举例|他说|她说|引用|转述|没有改变|没变|并没有',
      ).hasMatch(text) &&
      RegExp(
        r'以前.{0,80}现在|之前.{0,80}现在|现在(?:更|不再|改|只)|改为|改成|不再|说错了|纠正|其实我',
      ).hasMatch(text);

  static bool containsDirectChange(String message, String evidence) {
    final direct = message.replaceAll(
      RegExp(r'''“[^”]*”|「[^」]*」|『[^』]*』|"[^"]*"|‘[^’]*’|'[^']*' '''.trim()),
      '',
    );
    return direct.contains(evidence) && isChangeEvidence(direct);
  }
}
