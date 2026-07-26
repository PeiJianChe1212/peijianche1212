import '../models/ai_character.dart';
import '../models/life_moment.dart';
import '../models/shared_experience.dart';
import 'character_relationship_storage_service.dart';
import 'shared_experience_storage_service.dart';
import 'relationship_memory_service.dart';

class SharedExperienceService {
  SharedExperienceService({
    SharedExperienceStorageService? storage,
    CharacterRelationshipStorageService? relationshipStorage,
    RelationshipMemoryService? relationshipMemoryService,
  })  : _storage = storage ?? SharedExperienceStorageService(),
        _relationshipStorage =
            relationshipStorage ?? CharacterRelationshipStorageService(),
        _relationshipMemoryService =
            relationshipMemoryService ?? RelationshipMemoryService();

  final SharedExperienceStorageService _storage;
  final CharacterRelationshipStorageService _relationshipStorage;
  final RelationshipMemoryService _relationshipMemoryService;

  Future<bool> recordLifeEvent({
    required AiCharacter currentCharacter,
    required AiCharacter relatedCharacter,
    required LifeMomentCandidate event,
  }) async {
    final id = SharedExperience.buildId(
      sourceLifeEventId: event.id,
      firstId: currentCharacter.id,
      secondId: relatedCharacter.id,
    );

    final experience = SharedExperience(
      id: id,
      participantIds: [currentCharacter.id, relatedCharacter.id],
      participantNames: [
        currentCharacter.displayName,
        relatedCharacter.displayName,
      ],
      type: _inferType(event),
      summary: _buildSummary(event),
      detail: event.detail.trim(),
      occurredAt: event.occurredAt,
      createdAt: DateTime.now(),
      sourceLifeEventId: event.id,
      decisionId: event.decisionId,
      location: event.scene.trim(),
      importance: _inferImportance(event),
      relationshipOpportunityId: event.relationshipOpportunityId,
    );

    final inserted = await _storage.saveIfAbsent(experience);
    if (!inserted) return false;

    await _relationshipStorage.recordSharedEvent(
      firstId: currentCharacter.id,
      secondId: relatedCharacter.id,
      occurredAt: event.occurredAt,
      note: _relationshipNote(experience),
      experienceWeight: experience.importance,
    );
    await _relationshipMemoryService.rebuildForPair(
      currentCharacter.id,
      relatedCharacter.id,
    );
    return true;
  }

  SharedExperienceType _inferType(LifeMomentCandidate event) {
    final text = '${event.event} ${event.detail} ${event.shareHook}'.toLowerCase();
    if (_containsAny(text, ['争执', '不愉快', '闹别扭', '误会', '尴尬'])) {
      return SharedExperienceType.tension;
    }
    if (_containsAny(text, ['帮忙', '帮助', '照顾', '替他', '替她', '解围'])) {
      return SharedExperienceType.help;
    }
    if (_containsAny(text, ['合作', '一起完成', '共同处理', '分工', '准备'])) {
      return SharedExperienceType.cooperation;
    }
    if (_containsAny(text, ['生日', '庆祝', '纪念日', '节日', '聚会'])) {
      return SharedExperienceType.celebration;
    }
    if (_containsAny(text, ['旅行', '出游', '露营', '出发', '坐车', '散步'])) {
      return SharedExperienceType.travel;
    }
    if (_containsAny(text, ['聊了', '聊天', '谈起', '讨论', '说起'])) {
      return SharedExperienceType.conversation;
    }
    if (_containsAny(text, ['碰见', '遇见', '偶遇', '正好遇到'])) {
      return SharedExperienceType.encounter;
    }
    if (_containsAny(text, ['吃饭', '咖啡', '买东西', '逛', '做饭', '排队'])) {
      return SharedExperienceType.dailyLife;
    }
    return SharedExperienceType.other;
  }

  int _inferImportance(LifeMomentCandidate event) {
    final text = '${event.event} ${event.detail} ${event.shareHook}';
    if (_containsAny(text, ['第一次', '生日', '纪念日', '重要', '意外', '帮了大忙'])) {
      return 3;
    }
    if (_containsAny(text, ['合作', '帮助', '一起完成', '旅行', '出游'])) {
      return 2;
    }
    return 1;
  }

  String _buildSummary(LifeMomentCandidate event) {
    final eventText = event.event.trim();
    if (eventText.isNotEmpty) return eventText;
    final detail = event.detail.trim();
    if (detail.isNotEmpty) return detail;
    return '共同经历了一件日常小事';
  }

  String _relationshipNote(SharedExperience experience) {
    final location = experience.location.trim().isEmpty
        ? ''
        : '，地点：${experience.location.trim()}';
    return '最近共同经历：${experience.type.label}，${experience.summary}$location';
  }

  bool _containsAny(String text, List<String> values) {
    return values.any(text.contains);
  }
}
