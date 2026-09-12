import '../models/group_memory_event.dart';
import '../models/group_message.dart';

/// Deterministic, model-free extraction of a few long-lived group events.
///
/// This runs off the chat path and never calls a model. It keeps the speaker
/// attached to every candidate and may legitimately return zero events.
class GroupMemoryExtractor {
  const GroupMemoryExtractor();

  static const int maximumEventsPerBatch = 3;
  static const int minimumContentCharacters = 6;
  static const int maximumContentCharacters = 200;

  /// Durable first-person statements: plans, decisions, preferences, facts.
  static final RegExp _userDurablePattern = RegExp(
    r'(打算|准备|计划|决定|想好|要开始|开始|以后|下次|明年|下个月|下周|下个星期|月底|年底|'
    r'已经|刚刚|最近|一直|从来|第一次|最喜欢|最讨厌|最怕|不爱吃|不吃|不喝|不喜欢|喜欢|习惯|'
    r'过敏|生日|住在|搬家|搬去|换工作|考试|面试|出差|买|订|约好|报名|毕业|开学|入职|离职|结婚|分手)',
  );

  /// Character statements worth remembering: agreements, reminders, important
  /// observations about the user/group that are anchored in the group chat.
  static final RegExp _characterDurablePattern = RegExp(
    r'(约定|说好|答应|决定|提醒|建议|以后|下次|记得|别忘了|你不是|你以前|你之前|'
    r'你一直|你总是|我们|一起|计划|打算|准备|重要|秘密|保证|注意)',
  );

  static final RegExp _trivialPattern = RegExp(
    r'^(哈+|呵+|嘿+|嘻+|hi|hello|hey|在吗|在不在|早|早上好|晚上好|午安|晚安|好|好的|嗯+|哦+|'
    r'收到|谢谢|多谢|么么|好呀|好啊|哈哈+|嘿嘿+|呵呵+|好吧|行|可以|是的|对|不客气|'
    r'[\s,.!?~…，。！？、；：oO0]+)$',
    caseSensitive: false,
  );

  static final RegExp _firstPersonPattern = RegExp(r'(我|咱|俺)');

  List<GroupMemoryEvent> extract({
    required String groupId,
    String groupName = '',
    required List<GroupMessage> messages,
    Map<String, String> senderNames = const {},
    DateTime? now,
  }) {
    if (groupId.trim().isEmpty || messages.isEmpty) return const [];
    final time = now ?? DateTime.now();
    final result = <GroupMemoryEvent>[];

    for (final message in messages) {
      if (result.length >= maximumEventsPerBatch) break;
      final candidate = _candidateFor(
        message,
        groupId: groupId,
        groupName: groupName,
        senderNames: senderNames,
        now: time,
      );
      if (candidate == null) continue;
      if (result.any(
        (item) =>
            item.sourceMessageIds.toSet().intersection(
              candidate.sourceMessageIds.toSet(),
            ).isNotEmpty ||
            _similarText(item.content, candidate.content),
      )) {
        continue;
      }
      result.add(candidate);
    }
    return result;
  }

  GroupMemoryEvent? _candidateFor(
    GroupMessage message, {
    required String groupId,
    required String groupName,
    required Map<String, String> senderNames,
    required DateTime now,
  }) {
    if (message.senderType == GroupSenderType.system) return null;
    if (message.status == GroupMessageStatus.failed) return null;
    if (message.messageType != GroupMessageType.text) return null;
    if (message.sourceType == GroupMessageSource.system) return null;

    final clean = _cleanContent(message.content);
    if (clean.length < minimumContentCharacters) return null;
    if (_trivialPattern.hasMatch(clean)) return null;

    final isUser = message.senderType == GroupSenderType.user;
    if (isUser) {
      if (!_firstPersonPattern.hasMatch(clean)) return null;
      if (!_userDurablePattern.hasMatch(clean)) return null;
    } else {
      if (clean.length < 10) return null;
      if (!_characterDurablePattern.hasMatch(clean)) return null;
    }

    final speakerId = isUser ? 'user' : message.senderId.trim();
    if (speakerId.isEmpty) return null;
    final speakerLabel = isUser
        ? '用户'
        : _speakerName(speakerId, senderNames);
    final participants = <String>{
      speakerId,
      ...message.mentionedMemberIds.map((item) => item.trim()),
    }.where((item) => item.isNotEmpty).toList(growable: false);

    final content = isUser
        ? '用户提到：$clean'
        : '$speakerLabel说：$clean';
    return GroupMemoryEvent(
      id: 'group_event_${GroupMemoryStorageId.sanitize(groupId)}_${message.id}',
      groupId: groupId,
      groupName: groupName,
      content: content,
      speakerIds: [speakerId],
      participants: participants,
      occurredAt: message.createdAt,
      createdAt: now,
      updatedAt: now,
      sourceMessageIds: [message.id],
    );
  }

  String _speakerName(String speakerId, Map<String, String> names) {
    final name = names[speakerId]?.trim() ?? '';
    return name.isEmpty ? speakerId : name;
  }

  String _cleanContent(String value) {
    final clean = value
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'^[\s\-*•]+'), '')
        .trim();
    if (clean.length <= maximumContentCharacters) return clean;
    return '${clean.substring(0, maximumContentCharacters - 1).trimRight()}…';
  }

  bool _similarText(String first, String second) {
    final a = _normalize(first);
    final b = _normalize(second);
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b || a.contains(b) || b.contains(a)) return true;
    final left = a.split('').toSet();
    final right = b.split('').toSet();
    final union = left.union(right).length;
    return union > 0 && left.intersection(right).length / union >= 0.82;
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(
        RegExp(r"[\s，。！？、：；~～“”‘’()（）\[\]【】《》_\-]+"),
        '',
      );
}

/// Shared id sanitization for group-scoped ids.
abstract final class GroupMemoryStorageId {
  static String sanitize(String value) {
    final normalized = value.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return normalized.isEmpty ? 'unnamed_group' : normalized;
  }
}
