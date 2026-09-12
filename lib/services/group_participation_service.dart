import '../models/ai_character.dart';
import '../models/group_chat.dart';
import '../models/group_message.dart';

/// 单个群成员本轮的参与度评估（纯本地、可解释、无模型调用）。
class GroupParticipation {
  const GroupParticipation({
    required this.characterId,
    required this.score,
    required this.mentioned,
    required this.allowed,
    this.reasons = const [],
  });

  final String characterId;

  /// 越高越应该参与本轮。
  final double score;

  /// 是否被 @ 或直接点名（最高优先级强触发）。
  final bool mentioned;

  /// 是否允许进入候选：被 @ 时即使 allowInitiative=false 也允许。
  final bool allowed;

  /// 轻量原因标签，仅用于开发/测试，不写入任何 storage。
  final List<String> reasons;
}

/// 群聊发言门控：一次 planner 之前的本地预筛。
///
/// 只做加/减分与候选裁剪，不调用模型，也不替代 planner。
class GroupParticipationService {
  const GroupParticipationService();

  static const _stopWords = <String>{
    '今晚',
    '今天',
    '明天',
    '现在',
    '什么',
    '为什么',
    '怎么',
    '可以',
    '我们',
    '你们',
    '他们',
    '一个',
    '这个',
    '那个',
    '觉得',
    '知道',
    '有没有',
    '一起',
  };

  List<GroupParticipation> evaluate({
    required GroupChat group,
    required List<AiCharacter> members,
    required List<GroupMessage> messages,
    DateTime? now,
  }) {
    if (members.isEmpty) return const [];
    final time = now ?? DateTime.now();
    final latestUser = _latestUserMessage(messages);
    final latestUserContent = latestUser?.content ?? '';
    final mentionedIds = latestUser?.mentionedMemberIds.toSet() ?? const {};
    final userKeywords = _keywords(latestUserContent);
    final lastCharacterMessage = _lastCharacterMessage(messages, latestUser);
    final answersAfterUser = _countCharacterMessagesAfter(messages, latestUser);
    final memberById = {for (final item in group.members) item.characterId: item};

    final result = <GroupParticipation>[];
    for (final character in members) {
      final member = memberById[character.id];
      final reasons = <String>[];
      var score = 0.0;

      // 强触发：@ 优先，其次直接点名。
      final atMentioned = mentionedIds.contains(character.id);
      final named = _mentionsName(latestUserContent, character);
      final mentioned = atMentioned || named;
      if (atMentioned) {
        score += 1000;
        reasons.add('mentioned');
      } else if (named) {
        score += 800;
        reasons.add('directly_addressed');
      }

      // 上一位角色是否在对他说话。
      if (lastCharacterMessage != null &&
          lastCharacterMessage.senderId != character.id &&
          _mentionsName(lastCharacterMessage.content, character)) {
        score += 120;
        reasons.add('addressed_by_member');
      }

      // 话题相关度：用户消息与角色摘要的关键词重合。
      final haystack = _haystack(character);
      final hits = userKeywords
          .where((keyword) => haystack.contains(keyword))
          .take(3)
          .length;
      if (hits > 0) {
        score += hits * 15;
        reasons.add('topic_relevant');
      }

      // 冷热：刚说过话降温，久未参与升温。
      final lastSpokeAt = member?.lastSpokeAt;
      if (lastSpokeAt != null) {
        final gap = time.difference(lastSpokeAt);
        if (gap < const Duration(minutes: 10)) {
          score -= 40;
          reasons.add('cooldown');
        } else if (gap > const Duration(minutes: 60)) {
          score += 25;
          reasons.add('long_absent');
        }
      } else {
        score += 25;
        reasons.add('long_absent');
      }
      final recentCount = _recentSpeakerCount(
        messages,
        character.id,
        window: 10,
      );
      if (recentCount >= 2) {
        score -= 30;
        reasons.add('recently_active');
      }

      // 其他角色已经充分回答 → 非被 @ 的角色更容易沉默。
      if (answersAfterUser >= 2 && !mentioned) {
        score -= 60;
        reasons.add('already_answered');
      }

      // 群成员活跃度（字段终于参与调度）。
      final level = member?.activityLevel ?? 0.5;
      score += (level - 0.5) * 60;
      if (level >= 0.75) reasons.add('high_activity');
      if (level <= 0.25) reasons.add('low_activity');

      final initiativeDisabled = member?.allowInitiative == false;
      if (initiativeDisabled && !mentioned) reasons.add('initiative_disabled');

      result.add(
        GroupParticipation(
          characterId: character.id,
          score: score,
          mentioned: mentioned,
          allowed: mentioned || !initiativeDisabled,
          reasons: reasons,
        ),
      );
    }

    result.sort((a, b) => b.score.compareTo(a.score));
    return result;
  }

  GroupMessage? _latestUserMessage(List<GroupMessage> messages) {
    for (var index = messages.length - 1; index >= 0; index--) {
      if (messages[index].senderType == GroupSenderType.user) {
        return messages[index];
      }
    }
    return null;
  }

  GroupMessage? _lastCharacterMessage(
    List<GroupMessage> messages,
    GroupMessage? latestUser,
  ) {
    for (var index = messages.length - 1; index >= 0; index--) {
      final message = messages[index];
      if (message.senderType == GroupSenderType.character &&
          !identical(message, latestUser)) {
        return message;
      }
    }
    return null;
  }

  int _countCharacterMessagesAfter(
    List<GroupMessage> messages,
    GroupMessage? latestUser,
  ) {
    if (latestUser == null) return 0;
    var index = messages.lastIndexOf(latestUser);
    if (index < 0) index = messages.length - 1;
    var count = 0;
    for (var i = index + 1; i < messages.length; i++) {
      if (messages[i].senderType == GroupSenderType.character) count++;
    }
    return count;
  }

  int _recentSpeakerCount(
    List<GroupMessage> messages,
    String characterId, {
    required int window,
  }) {
    final start = messages.length <= window ? 0 : messages.length - window;
    var count = 0;
    for (var i = start; i < messages.length; i++) {
      final message = messages[i];
      if (message.senderType == GroupSenderType.character &&
          message.senderId == characterId) {
        count++;
      }
    }
    return count;
  }

  String _haystack(AiCharacter character) => [
    character.introduction,
    character.persona,
    character.remark,
    character.relationship,
  ].join(' ').toLowerCase();

  /// 名字匹配：多字名字直接包含；单字名字要求独立成词，避免误命中。
  bool _mentionsName(String content, AiCharacter character) {
    if (content.trim().isEmpty) return false;
    for (final raw in [character.displayName, character.characterName]) {
      final name = raw.trim();
      if (name.isEmpty) continue;
      if (name.length >= 2 && content.contains(name)) return true;
      if (name.length == 1) {
        final pattern = RegExp(
          '(^|[^A-Za-z0-9\\u4e00-\\u9fa5])${RegExp.escape(name)}'
          '([^A-Za-z0-9\\u4e00-\\u9fa5]|\$)',
        );
        if (pattern.hasMatch(content)) return true;
      }
    }
    return false;
  }

  Set<String> _keywords(String text) {
    final out = <String>{};
    final cleaned = text.replaceAll(
      RegExp(r'[^\u4e00-\u9fa5A-Za-z0-9]'),
      ' ',
    );
    for (final part in cleaned.split(RegExp(r'\s+'))) {
      if (part.isEmpty || part.length < 2) continue;
      if (part.length == 2) {
        out.add(part);
        continue;
      }
      for (var i = 0; i + 2 <= part.length; i++) {
        out.add(part.substring(i, i + 2));
      }
    }
    out.removeWhere(_stopWords.contains);
    return out;
  }
}
