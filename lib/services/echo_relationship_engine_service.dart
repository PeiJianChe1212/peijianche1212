import '../models/ai_character.dart';
import '../models/character_relationship.dart';

enum EchoRelationshipKind { lover, family, friend, acquaintance, stranger }

class EchoCommentTendency {
  const EchoCommentTendency({
    required this.kind,
    required this.intimacy,
    required this.probability,
    required this.tone,
  });

  final EchoRelationshipKind kind;
  final int intimacy;
  final double probability;
  final String tone;
}

/// First-version relationship decision boundary for Echo social feedback.
/// Future favor, conflicts, anniversaries and event modifiers can be added here
/// without coupling them to comment persistence or UI code.
class EchoRelationshipEngineService {
  const EchoRelationshipEngineService();

  EchoCommentTendency evaluate({
    required AiCharacter author,
    required AiCharacter commenter,
    CharacterRelationship? relationship,
    DateTime? now,
  }) {
    final note = relationship?.note.toLowerCase() ?? '';
    final kind = _kind(note, relationship?.stage);
    final shared = relationship?.sharedEventCount ?? 0;
    final knownDays = relationship == null
        ? 0
        : (now ?? DateTime.now()).difference(relationship.createdAt).inDays;
    final stageScore = switch (relationship?.stage) {
      CharacterRelationshipStage.friend => 62,
      CharacterRelationshipStage.cooperative => 48,
      CharacterRelationshipStage.familiar => 40,
      CharacterRelationshipStage.acquainted => 24,
      _ => 5,
    };
    final intimacy = (stageScore + shared.clamp(0, 8) * 4 + knownDays ~/ 30)
        .clamp(0, 100);
    final probability = switch (kind) {
      EchoRelationshipKind.lover => .86,
      EchoRelationshipKind.family => .72,
      EchoRelationshipKind.friend => .58,
      EchoRelationshipKind.acquaintance => .22,
      EchoRelationshipKind.stranger => .07,
    };
    final tone = switch (kind) {
      EchoRelationshipKind.lover => '关心、亲密、可以轻微调侃',
      EchoRelationshipKind.family => '自然关心近况',
      EchoRelationshipKind.friend => '轻松聊天、接住具体内容',
      EchoRelationshipKind.acquaintance => '克制友好',
      EchoRelationshipKind.stranger => '简短礼貌',
    };
    return EchoCommentTendency(
      kind: kind,
      intimacy: intimacy,
      probability: probability,
      tone: tone,
    );
  }

  EchoRelationshipKind _kind(String note, CharacterRelationshipStage? stage) {
    if (RegExp(r'恋人|情侣|伴侣|lover|partner').hasMatch(note)) {
      return EchoRelationshipKind.lover;
    }
    if (RegExp(r'家人|亲人|兄|姐|弟|妹|父|母|family').hasMatch(note)) {
      return EchoRelationshipKind.family;
    }
    if (stage == CharacterRelationshipStage.friend ||
        RegExp(r'朋友|好友|挚友|friend').hasMatch(note)) {
      return EchoRelationshipKind.friend;
    }
    if (stage != null && stage != CharacterRelationshipStage.aware) {
      return EchoRelationshipKind.acquaintance;
    }
    return EchoRelationshipKind.stranger;
  }
}
