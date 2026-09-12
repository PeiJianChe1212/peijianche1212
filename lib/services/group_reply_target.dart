import '../models/group_message.dart';

/// Who a speaking member is answering in this turn.
///
/// This is in-memory only: it is never written to GroupMessage / GroupReplyStep
/// storage. Group memory extraction keeps working off speaker identity alone.
enum GroupReplyTargetType { user, character, group }

class GroupReplyTarget {
  const GroupReplyTarget._(this.type, this.characterId);

  static const GroupReplyTarget user = GroupReplyTarget._(
    GroupReplyTargetType.user,
    'user',
  );
  static const GroupReplyTarget group = GroupReplyTarget._(
    GroupReplyTargetType.group,
    'group',
  );

  const GroupReplyTarget.character(String characterId)
    : this._(GroupReplyTargetType.character, characterId);

  final GroupReplyTargetType type;
  final String characterId;

  bool get isUser => type == GroupReplyTargetType.user;
  bool get isGroup => type == GroupReplyTargetType.group;
  bool get isCharacter => type == GroupReplyTargetType.character;

  String get id => isCharacter ? characterId : type.name;

  /// Stable key used by diagnostics/tests.
  String describe([Map<String, String> names = const {}]) {
    switch (type) {
      case GroupReplyTargetType.user:
        return 'user';
      case GroupReplyTargetType.group:
        return 'group';
      case GroupReplyTargetType.character:
        final name = names[characterId]?.trim() ?? '';
        return name.isEmpty ? characterId : '$name($characterId)';
    }
  }

  @override
  bool operator ==(Object other) =>
      other is GroupReplyTarget &&
      other.type == type &&
      other.characterId == characterId;

  @override
  int get hashCode => Object.hash(type, characterId);

  @override
  String toString() => 'GroupReplyTarget(${describe()})';
}

/// Local, model-free reply-target selection.
///
/// It never forces member-to-member interaction: when the previous member only
/// made a long standalone statement the target degrades to the open floor, and
/// the caller may still end up staying silent via participation.
class GroupReplyTargetResolver {
  const GroupReplyTargetResolver();

  /// Reaction-worthy previously spoken message: a question/challenge or a short
  /// remark. Long standalone statements are treated as open-floor contributions.
  static const int shortRemarkCharacters = 40;

  /// A turn may only start from a user message. Character messages never open a
  /// new round, which is what prevents A -> B -> A infinite chatter.
  bool isTurnTrigger(GroupMessage? latest) =>
      latest != null && latest.senderType == GroupSenderType.user;

  GroupReplyTarget resolve({
    required String speakerCharacterId,
    required List<GroupMessage> messages,
    String speakerName = '',
    List<String> participationReasons = const [],
    String? plannerTargetId,
  }) {
    final self = speakerCharacterId.trim();
    if (self.isEmpty || messages.isEmpty) return GroupReplyTarget.user;

    final latestUser = _latestUserMessage(messages);
    final previousCharacter = _previousTurnCharacterMessage(messages, self);

    // 1. 用户直接 @ / 点名当前角色 → 回应用户。
    if (_addressedByUser(latestUser, self, speakerName)) {
      return GroupReplyTarget.user;
    }

    // 2. G3.2 participation 明确判定被点名 → 回应用户。
    if (participationReasons.contains('mentioned') ||
        participationReasons.contains('directly_addressed')) {
      return GroupReplyTarget.user;
    }

    // 3. 上一位角色明确点名当前角色 → 优先回应那位角色。
    if (previousCharacter != null &&
        _mentionsName(previousCharacter.content, speakerName, self)) {
      return GroupReplyTarget.character(previousCharacter.senderId);
    }

    // 4. planner 在同一次调用里给出的目标（只在目标真实存在于本轮时采纳）。
    final hinted = _fromPlannerHint(plannerTargetId, messages, self);
    if (hinted != null) return hinted;

    // 5. 上一位角色刚提出问题/反驳/补充 → 可回应那位角色；否则开放发言。
    if (previousCharacter != null) {
      return _isReactionWorthy(previousCharacter.content)
          ? GroupReplyTarget.character(previousCharacter.senderId)
          : GroupReplyTarget.group;
    }

    // 6. 本轮第一个发言者：回应触发本轮的 user。
    return GroupReplyTarget.user;
  }

  GroupMessage? _latestUserMessage(List<GroupMessage> messages) {
    for (var index = messages.length - 1; index >= 0; index--) {
      if (messages[index].senderType == GroupSenderType.user) {
        return messages[index];
      }
    }
    return null;
  }

  /// Last character message of the current turn (after the latest user message).
  /// A failed generation simply leaves no message, so callers fall back instead
  /// of quoting something that never existed.
  GroupMessage? _previousTurnCharacterMessage(
    List<GroupMessage> messages,
    String self,
  ) {
    final start = _turnStartIndex(messages);
    for (var index = messages.length - 1; index >= start; index--) {
      final message = messages[index];
      if (message.senderType == GroupSenderType.character &&
          message.senderId != self) {
        return message;
      }
    }
    return null;
  }

  int _turnStartIndex(List<GroupMessage> messages) {
    for (var index = messages.length - 1; index >= 0; index--) {
      if (messages[index].senderType == GroupSenderType.user) {
        return index + 1;
      }
    }
    return 0;
  }

  GroupReplyTarget? _fromPlannerHint(
    String? hint,
    List<GroupMessage> messages,
    String self,
  ) {
    final raw = hint?.trim() ?? '';
    if (raw.isEmpty) return null;
    if (raw == 'user') return GroupReplyTarget.user;
    if (raw == 'group' || raw == 'all' || raw == 'everyone') {
      return GroupReplyTarget.group;
    }
    if (raw == self) return null;
    final start = _turnStartIndex(messages);
    for (var index = start; index < messages.length; index++) {
      final message = messages[index];
      if (message.senderType == GroupSenderType.character &&
          message.senderId == raw &&
          message.senderId != self) {
        return GroupReplyTarget.character(raw);
      }
    }
    return null;
  }

  bool _addressedByUser(
    GroupMessage? latestUser,
    String self,
    String speakerName,
  ) {
    if (latestUser == null) return false;
    if (latestUser.mentionedMemberIds.contains(self)) return true;
    return _mentionsName(latestUser.content, speakerName, self);
  }

  bool _mentionsName(String content, String speakerName, String self) {
    final text = content.trim();
    if (text.isEmpty) return false;
    final name = speakerName.trim();
    if (name.length >= 2 && text.contains(name)) return true;
    if (text.contains('@$self')) return true;
    if (name.length == 1) {
      final pattern = RegExp(
        '(^|[^A-Za-z0-9\\u4e00-\\u9fa5])${RegExp.escape(name)}'
        '([^A-Za-z0-9\\u4e00-\\u9fa5]|\$)',
      );
      if (pattern.hasMatch(text)) return true;
    }
    return false;
  }

  bool _isReactionWorthy(String content) {
    final text = content.trim();
    if (text.isEmpty) return false;
    if (text.length <= shortRemarkCharacters) return true;
    if (RegExp(r'[?？]$').hasMatch(text)) return true;
    return RegExp(r'(吗|呢|吧|么)[?？！!。~～]?$').hasMatch(text);
  }
}
