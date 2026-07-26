import '../models/ai_character.dart';
import '../models/character_relationship.dart';
import '../models/relationship_memory.dart';
import '../models/relationship_network.dart';
import '../models/shared_experience.dart';
import 'character_registry_service.dart';
import 'character_relationship_storage_service.dart';
import 'relationship_memory_service.dart';
import 'shared_experience_storage_service.dart';

class RelationshipNetworkService {
  RelationshipNetworkService({
    CharacterRegistryService? registry,
    CharacterRelationshipStorageService? relationshipStorage,
    SharedExperienceStorageService? experienceStorage,
    RelationshipMemoryService? memoryService,
  })  : _registry = registry ?? CharacterRegistryService(),
        _relationshipStorage =
            relationshipStorage ?? CharacterRelationshipStorageService(),
        _experienceStorage =
            experienceStorage ?? SharedExperienceStorageService(),
        _memoryService = memoryService ?? RelationshipMemoryService();

  final CharacterRegistryService _registry;
  final CharacterRelationshipStorageService _relationshipStorage;
  final SharedExperienceStorageService _experienceStorage;
  final RelationshipMemoryService _memoryService;

  Future<RelationshipNetworkSnapshot> buildSnapshot({
    List<AiCharacter>? characters,
  }) async {
    final allCharacters = characters ?? await _registry.loadCharacters();
    final validCharacters = allCharacters
        .where((item) => item.id.trim().isNotEmpty)
        .toList();
    final characterById = {
      for (final item in validCharacters) item.id: item,
    };

    final relationships =
        await _relationshipStorage.ensureForCharacters(validCharacters);
    final experiences = await _experienceStorage.loadAll();
    final experiencesByRelationshipId = <String, List<SharedExperience>>{};

    for (final experience in experiences) {
      final participantIds = experience.participantIds
          .where(characterById.containsKey)
          .toSet()
          .toList();
      for (var i = 0; i < participantIds.length; i++) {
        for (var j = i + 1; j < participantIds.length; j++) {
          final relationshipId = CharacterRelationship.buildId(
            participantIds[i],
            participantIds[j],
          );
          experiencesByRelationshipId
              .putIfAbsent(relationshipId, () => <SharedExperience>[])
              .add(experience);
        }
      }
    }

    final edges = <RelationshipNetworkEdge>[];
    for (final relationship in relationships) {
      final characterA = characterById[relationship.characterIdA];
      final characterB = characterById[relationship.characterIdB];
      if (characterA == null || characterB == null) continue;

      final pairExperiences =
          experiencesByRelationshipId[relationship.id] ?? const [];
      final memory = pairExperiences.isEmpty
          ? null
          : await _memoryService.rebuildForPair(
              relationship.characterIdA,
              relationship.characterIdB,
              experiences: pairExperiences,
            );
      final weightedCount = pairExperiences.fold<int>(
        0,
        (total, item) => total + item.importance,
      );
      final latestExperienceAt = pairExperiences.isEmpty
          ? relationship.lastSharedEventAt
          : pairExperiences
              .map((item) => item.occurredAt)
              .reduce((a, b) => a.isAfter(b) ? a : b);

      edges.add(
        RelationshipNetworkEdge(
          id: relationship.id,
          characterIdA: relationship.characterIdA,
          characterIdB: relationship.characterIdB,
          characterNameA: characterA.displayName,
          characterNameB: characterB.displayName,
          stage: relationship.stage,
          sharedExperienceCount: pairExperiences.length,
          weightedExperienceCount: weightedCount,
          updatedAt: _latestDate(
            relationship.updatedAt,
            memory?.updatedAt,
            latestExperienceAt,
          ),
          lastInteractionAt: latestExperienceAt,
          summary: memory?.summary ?? _defaultSummary(relationship.stage),
          recentMemories: memory?.recentMemories ?? const [],
          sharedPatterns: memory?.sharedPatterns ?? const [],
          familiarity: memory?.familiarity ?? 0,
          trust: memory?.trust ?? 0,
          cooperation: memory?.cooperation ?? 0,
          respect: memory?.respect ?? 0,
          ease: memory?.ease ?? 0,
        ),
      );
    }

    final nodes = validCharacters.map((character) {
      final connections = edges.where((edge) => edge.contains(character.id));
      final activeConnections =
          connections.where((edge) => edge.hasActualInteraction).toList();
      DateTime? lastInteractionAt;
      for (final edge in activeConnections) {
        final time = edge.lastInteractionAt;
        if (time != null &&
            (lastInteractionAt == null || time.isAfter(lastInteractionAt))) {
          lastInteractionAt = time;
        }
      }
      return RelationshipNetworkNode(
        characterId: character.id,
        displayName: character.displayName,
        avatarPath: character.avatarPath,
        isBuiltIn: character.isBuiltIn,
        createdAt: character.createdAt,
        connectionCount: connections.length,
        activeConnectionCount: activeConnections.length,
        lastInteractionAt: lastInteractionAt,
      );
    }).toList();

    edges.sort((a, b) {
      final aTime = a.lastInteractionAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.lastInteractionAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });

    return RelationshipNetworkSnapshot(
      nodes: nodes,
      edges: edges,
      generatedAt: DateTime.now(),
    );
  }

  Future<RelationshipNetworkEdge?> findConnection(
    String firstId,
    String secondId,
  ) async {
    final snapshot = await buildSnapshot();
    return snapshot.edgeFor(firstId, secondId);
  }

  Future<List<RelationshipNetworkEdge>> connectionsFor(
    String characterId, {
    bool onlyWithExperience = false,
  }) async {
    final snapshot = await buildSnapshot();
    return snapshot.connectionsFor(
      characterId,
      onlyWithExperience: onlyWithExperience,
    );
  }

  Future<List<RelationshipNetworkEdge>> recentConnections({
    int limit = 10,
  }) async {
    final snapshot = await buildSnapshot();
    final items = snapshot.edges
        .where((edge) => edge.lastInteractionAt != null)
        .toList();
    if (limit <= 0 || items.length <= limit) return items;
    return items.take(limit).toList();
  }

  String buildCompactContext({
    required RelationshipNetworkSnapshot snapshot,
    required String currentCharacterId,
    int maxConnections = 6,
  }) {
    final connections = snapshot.connectionsFor(currentCharacterId);
    if (connections.isEmpty) return '';
    final selected = connections.take(maxConnections);
    final lines = selected.map((edge) {
      final otherName = edge.otherCharacterName(currentCharacterId) ?? '其他角色';
      final latest = edge.recentMemories.isEmpty
          ? ''
          : '；最近：${edge.recentMemories.first}';
      final patterns = edge.sharedPatterns.isEmpty
          ? ''
          : '；相处规律：${edge.sharedPatterns.join('、')}';
      return '- 与$otherName：${edge.stage.label}；${edge.summary}$patterns$latest';
    }).join('\n');
    return lines;
  }

  DateTime _latestDate(
    DateTime first,
    DateTime? second,
    DateTime? third,
  ) {
    var latest = first;
    if (second != null && second.isAfter(latest)) latest = second;
    if (third != null && third.isAfter(latest)) latest = third;
    return latest;
  }

  String _defaultSummary(CharacterRelationshipStage stage) => switch (stage) {
        CharacterRelationshipStage.aware => '只知道彼此存在，尚未真正相处。',
        CharacterRelationshipStage.acquainted => '已经有过实际接触，但仍在互相了解。',
        CharacterRelationshipStage.familiar => '相处开始自然，已经了解彼此的一些习惯。',
        CharacterRelationshipStage.cooperative => '遇到具体事情时能够自然分工并配合。',
        CharacterRelationshipStage.friend => '已经形成稳定而自然的朋友关系。',
      };
}
