enum CharacterRelationshipStage {
  aware,
  acquainted,
  familiar,
  cooperative,
  friend,
}

extension CharacterRelationshipStageText on CharacterRelationshipStage {
  String get label => switch (this) {
        CharacterRelationshipStage.aware => '知道彼此存在',
        CharacterRelationshipStage.acquainted => '认识',
        CharacterRelationshipStage.familiar => '熟悉',
        CharacterRelationshipStage.cooperative => '能够合作',
        CharacterRelationshipStage.friend => '朋友',
      };
}

class CharacterRelationship {
  const CharacterRelationship({
    required this.id,
    required this.characterIdA,
    required this.characterIdB,
    required this.stage,
    required this.createdAt,
    required this.updatedAt,
    this.sharedEventCount = 0,
    this.note = '',
    this.lastSharedEventAt,
  });

  final String id;
  final String characterIdA;
  final String characterIdB;
  final CharacterRelationshipStage stage;
  final int sharedEventCount;
  final String note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastSharedEventAt;

  bool contains(String characterId) =>
      characterIdA == characterId || characterIdB == characterId;

  String? otherCharacterId(String characterId) {
    if (characterIdA == characterId) return characterIdB;
    if (characterIdB == characterId) return characterIdA;
    return null;
  }

  CharacterRelationship copyWith({
    CharacterRelationshipStage? stage,
    int? sharedEventCount,
    String? note,
    DateTime? updatedAt,
    DateTime? lastSharedEventAt,
    bool clearLastSharedEventAt = false,
  }) {
    return CharacterRelationship(
      id: id,
      characterIdA: characterIdA,
      characterIdB: characterIdB,
      stage: stage ?? this.stage,
      sharedEventCount: sharedEventCount ?? this.sharedEventCount,
      note: note ?? this.note,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastSharedEventAt: clearLastSharedEventAt
          ? null
          : lastSharedEventAt ?? this.lastSharedEventAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'characterIdA': characterIdA,
        'characterIdB': characterIdB,
        'stage': stage.name,
        'sharedEventCount': sharedEventCount,
        'note': note,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'lastSharedEventAt': lastSharedEventAt?.toIso8601String(),
      };

  factory CharacterRelationship.fromJson(Map<dynamic, dynamic> json) {
    final characterIdA = json['characterIdA']?.toString().trim() ?? '';
    final characterIdB = json['characterIdB']?.toString().trim() ?? '';
    final now = DateTime.now();
    return CharacterRelationship(
      id: json['id']?.toString().trim().isNotEmpty == true
          ? json['id'].toString().trim()
          : buildId(characterIdA, characterIdB),
      characterIdA: characterIdA,
      characterIdB: characterIdB,
      stage: CharacterRelationshipStage.values.firstWhere(
        (item) => item.name == json['stage']?.toString(),
        orElse: () => CharacterRelationshipStage.aware,
      ),
      sharedEventCount: int.tryParse(json['sharedEventCount']?.toString() ?? '') ?? 0,
      note: json['note']?.toString().trim() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? now,
      lastSharedEventAt:
          DateTime.tryParse(json['lastSharedEventAt']?.toString() ?? ''),
    );
  }

  static String buildId(String firstId, String secondId) {
    final ids = [firstId.trim(), secondId.trim()]..sort();
    return 'relationship_${ids[0]}__${ids[1]}';
  }
}
