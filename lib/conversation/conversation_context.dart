import '../models/chat_message.dart';

class ConversationContext {
  const ConversationContext({
    required this.userTurnCount,
    required this.recentAssistantReplies,
    required this.latestUserMessage,
    required this.actionMentions,
    required this.repeatedActionGroups,
    required this.shouldInviteSelfSharing,
  });

  final int userTurnCount;
  final List<String> recentAssistantReplies;
  final String latestUserMessage;
  final int actionMentions;
  final Set<String> repeatedActionGroups;
  final bool shouldInviteSelfSharing;

  bool get actionCoolingRequired =>
      actionMentions >= 2 || repeatedActionGroups.isNotEmpty;

  factory ConversationContext.fromMessages(List<ChatMessage> messages) {
    final valid = messages
        .where(
          (message) => message.role == 'user' || message.role == 'assistant',
        )
        .toList();
    final userMessages = valid.where((message) => message.role == 'user').toList();
    final assistantMessages = valid
        .where((message) => message.role == 'assistant')
        .toList();
    final recentAssistant = assistantMessages.length > 6
        ? assistantMessages.sublist(assistantMessages.length - 6)
        : assistantMessages;

    final groupCounts = <String, int>{};
    var actionMentions = 0;
    for (final message in recentAssistant) {
      for (final entry in _actionGroups.entries) {
        if (entry.value.any(message.content.contains)) {
          actionMentions += 1;
          groupCounts.update(entry.key, (value) => value + 1, ifAbsent: () => 1);
        }
      }
    }

    final repeated = groupCounts.entries
        .where((entry) => entry.value >= 2)
        .map((entry) => entry.key)
        .toSet();
    final userTurnCount = userMessages.length;

    return ConversationContext(
      userTurnCount: userTurnCount,
      recentAssistantReplies: recentAssistant
          .map((message) => message.content)
          .toList(growable: false),
      latestUserMessage: userMessages.isEmpty ? '' : userMessages.last.content,
      actionMentions: actionMentions,
      repeatedActionGroups: repeated,
      shouldInviteSelfSharing:
          userTurnCount >= 3 && userTurnCount % 4 == 0,
    );
  }

  static const Map<String, List<String>> _actionGroups = {
    '拥抱类': ['抱住', '抱紧', '拥入', '搂住', '揽进', '圈进怀里', '怀里'],
    '亲吻类': ['亲了', '亲吻', '吻上', '吻了', '亲额头', '亲你', '落下一吻'],
    '贴近类': ['贴近', '靠近', '蹭了蹭', '鼻尖', '抵着额头', '贴着你'],
    '触碰类': ['摸了摸', '揉了揉', '捏了捏', '抚过', '扣住手腕', '牵住'],
  };
}
