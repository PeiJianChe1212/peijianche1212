import '../models/character_relationship.dart';
import '../models/relationship_memory.dart';
import '../models/shared_experience.dart';
import 'character_relationship_storage_service.dart';
import 'relationship_memory_storage_service.dart';
import 'shared_experience_storage_service.dart';

class RelationshipMemoryService {
  RelationshipMemoryService({
    RelationshipMemoryStorageService? storage,
    SharedExperienceStorageService? experienceStorage,
    CharacterRelationshipStorageService? relationshipStorage,
  })  : _storage = storage ?? RelationshipMemoryStorageService(),
        _experienceStorage =
            experienceStorage ?? SharedExperienceStorageService(),
        _relationshipStorage =
            relationshipStorage ?? CharacterRelationshipStorageService();

  final RelationshipMemoryStorageService _storage;
  final SharedExperienceStorageService _experienceStorage;
  final CharacterRelationshipStorageService _relationshipStorage;

  Future<RelationshipMemory?> ensureForPair(
    String firstId,
    String secondId,
  ) async {
    final experiences = await _experienceStorage.loadForPair(firstId, secondId);
    if (experiences.isEmpty) return null;

    final existing = await _storage.find(firstId, secondId);
    if (existing != null &&
        existing.generatedFromExperienceCount == experiences.length) {
      return existing;
    }
    return rebuildForPair(firstId, secondId, experiences: experiences);
  }

  Future<RelationshipMemory?> rebuildForPair(
    String firstId,
    String secondId, {
    List<SharedExperience>? experiences,
  }) async {
    final items = experiences ??
        await _experienceStorage.loadForPair(firstId, secondId);
    if (items.isEmpty) return null;

    final relationship = await _relationshipStorage.find(firstId, secondId);
    final typeCounts = <SharedExperienceType, int>{};
    var weightedCount = 0;
    for (final item in items) {
      typeCounts[item.type] = (typeCounts[item.type] ?? 0) + 1;
      weightedCount += item.importance;
    }

    final familiarity = (weightedCount * 12).clamp(0, 100).toInt();
    final cooperation = (((typeCounts[SharedExperienceType.cooperation] ?? 0) * 22) +
            ((typeCounts[SharedExperienceType.help] ?? 0) * 18) +
            ((typeCounts[SharedExperienceType.dailyLife] ?? 0) * 6))
        .clamp(0, 100)
        .toInt();
    final trust = (((typeCounts[SharedExperienceType.help] ?? 0) * 24) +
            ((typeCounts[SharedExperienceType.cooperation] ?? 0) * 14) +
            weightedCount * 4)
        .clamp(0, 100)
        .toInt();
    final respect =
        (35 + cooperation ~/ 2 + trust ~/ 3).clamp(0, 100).toInt();
    final tensionCount = typeCounts[SharedExperienceType.tension] ?? 0;
    final ease = (25 +
            (typeCounts[SharedExperienceType.conversation] ?? 0) * 12 +
            (typeCounts[SharedExperienceType.dailyLife] ?? 0) * 10 +
            (typeCounts[SharedExperienceType.celebration] ?? 0) * 10 -
            tensionCount * 10)
        .clamp(0, 100)
        .toInt();

    final sortedIds = [firstId, secondId]..sort();
    final memory = RelationshipMemory(
      id: RelationshipMemory.buildId(firstId, secondId),
      characterIdA: relationship?.characterIdA ?? sortedIds[0],
      characterIdB: relationship?.characterIdB ?? sortedIds[1],
      summary: _buildSummary(
        relationship?.stage ?? CharacterRelationshipStage.acquainted,
        typeCounts,
        tensionCount,
      ),
      recentMemories: items
          .take(3)
          .map((item) {
            final place = item.location.trim().isEmpty
                ? ''
                : '（${item.location.trim()}）';
            return '${item.type.label}：${item.summary}$place';
          })
          .toList(),
      sharedPatterns: _buildPatterns(typeCounts),
      generatedFromExperienceCount: items.length,
      updatedAt: DateTime.now(),
      familiarity: familiarity,
      trust: trust,
      cooperation: cooperation,
      respect: respect,
      ease: ease,
    );
    await _storage.save(memory);
    return memory;
  }

  String _buildSummary(
    CharacterRelationshipStage stage,
    Map<SharedExperienceType, int> counts,
    int tensionCount,
  ) {
    final parts = <String>[
      switch (stage) {
        CharacterRelationshipStage.aware => '只知道彼此存在，尚未真正相处',
        CharacterRelationshipStage.acquainted => '已经有过实际接触，但仍在互相了解',
        CharacterRelationshipStage.familiar => '相处开始自然，已经了解彼此的一些习惯',
        CharacterRelationshipStage.cooperative => '遇到具体事情时能够自然分工并配合',
        CharacterRelationshipStage.friend => '已经形成稳定而自然的朋友关系',
      },
    ];

    if ((counts[SharedExperienceType.cooperation] ?? 0) > 0) {
      parts.add('共同做事时有过配合');
    }
    if ((counts[SharedExperienceType.help] ?? 0) > 0) {
      parts.add('有过互相帮助的经历');
    }
    if ((counts[SharedExperienceType.dailyLife] ?? 0) >= 2) {
      parts.add('普通日常中的相处正在增多');
    }
    if (tensionCount > 0) {
      parts.add('偶尔有过轻微不愉快，但不足以定义为敌对');
    }
    return '${parts.join('；')}。';
  }

  List<String> _buildPatterns(Map<SharedExperienceType, int> counts) {
    final patterns = <String>[];
    if ((counts[SharedExperienceType.cooperation] ?? 0) >= 2) {
      patterns.add('已经形成过重复的合作模式');
    }
    if ((counts[SharedExperienceType.conversation] ?? 0) >= 2) {
      patterns.add('见面时能够自然聊上几句');
    }
    if ((counts[SharedExperienceType.dailyLife] ?? 0) >= 2) {
      patterns.add('在普通生活场景中经常碰面');
    }
    if ((counts[SharedExperienceType.help] ?? 0) >= 2) {
      patterns.add('遇到麻烦时有互相帮忙的倾向');
    }
    if ((counts[SharedExperienceType.travel] ?? 0) >= 2) {
      patterns.add('共同出行已经不是第一次');
    }
    return patterns.take(3).toList();
  }
}
