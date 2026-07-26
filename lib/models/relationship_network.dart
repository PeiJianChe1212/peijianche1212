import 'character_relationship.dart';
import 'relationship_memory.dart';

class RelationshipNetworkNode {
  const RelationshipNetworkNode({
    required this.characterId,
    required this.displayName,
    required this.isBuiltIn,
    required this.createdAt,
    this.avatarPath = '',
    this.connectionCount = 0,
    this.activeConnectionCount = 0,
    this.lastInteractionAt,
  });

  final String characterId;
  final String displayName;
  final String avatarPath;
  final bool isBuiltIn;
  final DateTime createdAt;
  final int connectionCount;
  final int activeConnectionCount;
  final DateTime? lastInteractionAt;

  RelationshipNetworkNode copyWith({
    int? connectionCount,
    int? activeConnectionCount,
    DateTime? lastInteractionAt,
  }) {
    return RelationshipNetworkNode(
      characterId: characterId,
      displayName: displayName,
      avatarPath: avatarPath,
      isBuiltIn: isBuiltIn,
      createdAt: createdAt,
      connectionCount: connectionCount ?? this.connectionCount,
      activeConnectionCount:
          activeConnectionCount ?? this.activeConnectionCount,
      lastInteractionAt: lastInteractionAt ?? this.lastInteractionAt,
    );
  }
}

class RelationshipNetworkEdge {
  const RelationshipNetworkEdge({
    required this.id,
    required this.characterIdA,
    required this.characterIdB,
    required this.characterNameA,
    required this.characterNameB,
    required this.stage,
    required this.sharedExperienceCount,
    required this.weightedExperienceCount,
    required this.updatedAt,
    required this.summary,
    required this.recentMemories,
    required this.sharedPatterns,
    this.lastInteractionAt,
    this.familiarity = 0,
    this.trust = 0,
    this.cooperation = 0,
    this.respect = 0,
    this.ease = 0,
  });

  final String id;
  final String characterIdA;
  final String characterIdB;
  final String characterNameA;
  final String characterNameB;
  final CharacterRelationshipStage stage;
  final int sharedExperienceCount;
  final int weightedExperienceCount;
  final DateTime updatedAt;
  final DateTime? lastInteractionAt;
  final String summary;
  final List<String> recentMemories;
  final List<String> sharedPatterns;
  final int familiarity;
  final int trust;
  final int cooperation;
  final int respect;
  final int ease;

  bool contains(String characterId) =>
      characterIdA == characterId || characterIdB == characterId;

  String? otherCharacterId(String characterId) {
    if (characterIdA == characterId) return characterIdB;
    if (characterIdB == characterId) return characterIdA;
    return null;
  }

  String? otherCharacterName(String characterId) {
    if (characterIdA == characterId) return characterNameB;
    if (characterIdB == characterId) return characterNameA;
    return null;
  }

  bool get hasActualInteraction => sharedExperienceCount > 0;

  RelationshipMemory toRelationshipMemory() => RelationshipMemory(
        id: RelationshipMemory.buildId(characterIdA, characterIdB),
        characterIdA: characterIdA,
        characterIdB: characterIdB,
        summary: summary,
        recentMemories: recentMemories,
        sharedPatterns: sharedPatterns,
        generatedFromExperienceCount: sharedExperienceCount,
        updatedAt: updatedAt,
        familiarity: familiarity,
        trust: trust,
        cooperation: cooperation,
        respect: respect,
        ease: ease,
      );
}

class RelationshipNetworkSnapshot {
  const RelationshipNetworkSnapshot({
    required this.nodes,
    required this.edges,
    required this.generatedAt,
  });

  final List<RelationshipNetworkNode> nodes;
  final List<RelationshipNetworkEdge> edges;
  final DateTime generatedAt;

  RelationshipNetworkNode? nodeFor(String characterId) {
    for (final node in nodes) {
      if (node.characterId == characterId) return node;
    }
    return null;
  }

  RelationshipNetworkEdge? edgeFor(String firstId, String secondId) {
    final id = CharacterRelationship.buildId(firstId, secondId);
    for (final edge in edges) {
      if (edge.id == id) return edge;
    }
    return null;
  }

  List<RelationshipNetworkEdge> connectionsFor(
    String characterId, {
    bool onlyWithExperience = false,
  }) {
    final items = edges.where((edge) {
      if (!edge.contains(characterId)) return false;
      return !onlyWithExperience || edge.hasActualInteraction;
    }).toList();
    items.sort((a, b) {
      final aTime = a.lastInteractionAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.lastInteractionAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final timeCompare = bTime.compareTo(aTime);
      if (timeCompare != 0) return timeCompare;
      return b.weightedExperienceCount.compareTo(a.weightedExperienceCount);
    });
    return items;
  }
}
