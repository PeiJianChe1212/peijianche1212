enum RelationshipGrowthEventType {
  initialized,
  chat,
  echoInteraction,
  gift,
  special,
}

class RelationshipStageDefinition {
  const RelationshipStageDefinition({
    required this.minLevel,
    required this.maxLevel,
    required this.name,
  });

  final int minLevel;
  final int maxLevel;
  final String name;
}

class RelationshipGrowthConfig {
  const RelationshipGrowthConfig({required this.stages});

  final List<RelationshipStageDefinition> stages;

  static const standard = RelationshipGrowthConfig(
    stages: [
      RelationshipStageDefinition(minLevel: 1, maxLevel: 10, name: '相识'),
      RelationshipStageDefinition(minLevel: 11, maxLevel: 20, name: '熟悉'),
      RelationshipStageDefinition(minLevel: 21, maxLevel: 30, name: '交流'),
      RelationshipStageDefinition(minLevel: 31, maxLevel: 40, name: '信赖'),
      RelationshipStageDefinition(minLevel: 41, maxLevel: 50, name: '亲密'),
      RelationshipStageDefinition(minLevel: 51, maxLevel: 60, name: '默契'),
      RelationshipStageDefinition(minLevel: 61, maxLevel: 70, name: '依恋'),
      RelationshipStageDefinition(minLevel: 71, maxLevel: 80, name: '共鸣'),
      RelationshipStageDefinition(minLevel: 81, maxLevel: 90, name: '羁绊'),
      RelationshipStageDefinition(minLevel: 91, maxLevel: 100, name: '永恒'),
    ],
  );

  String stageFor(int level) {
    final safeLevel = level.clamp(1, 100);
    return stages
        .firstWhere(
          (stage) => safeLevel >= stage.minLevel && safeLevel <= stage.maxLevel,
          orElse: () => stages.first,
        )
        .name;
  }

  int experienceForNextLevel(int level) =>
      level >= 100 ? 0 : 100 + ((level - 1) * 20);
}

class RelationshipGrowthEvent {
  const RelationshipGrowthEvent({
    required this.id,
    required this.type,
    required this.title,
    required this.experience,
    required this.occurredAt,
    this.detail = '',
  });

  final String id;
  final RelationshipGrowthEventType type;
  final String title;
  final String detail;
  final int experience;
  final DateTime occurredAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'title': title,
    'detail': detail,
    'experience': experience,
    'occurredAt': occurredAt.toIso8601String(),
  };

  factory RelationshipGrowthEvent.fromJson(Map<dynamic, dynamic> json) =>
      RelationshipGrowthEvent(
        id: _text(json['id']),
        type: RelationshipGrowthEventType.values.firstWhere(
          (value) => value.name == _text(json['type']),
          orElse: () => RelationshipGrowthEventType.special,
        ),
        title: _text(json['title']),
        detail: _text(json['detail']),
        experience: _nonNegativeInt(json['experience']),
        occurredAt:
            DateTime.tryParse(_text(json['occurredAt'])) ?? DateTime.now(),
      );
}

enum RelationshipGiftType { flower, letter, smallGift, collectible }

extension RelationshipGiftTypeText on RelationshipGiftType {
  String get label => const {
    RelationshipGiftType.flower: '一束花',
    RelationshipGiftType.letter: '一封信',
    RelationshipGiftType.smallGift: '一份小礼物',
    RelationshipGiftType.collectible: '一件收藏品',
  }[this]!;

  int get experience => const {
    RelationshipGiftType.flower: 12,
    RelationshipGiftType.letter: 15,
    RelationshipGiftType.smallGift: 18,
    RelationshipGiftType.collectible: 24,
  }[this]!;
}

class RelationshipGiftRecord {
  const RelationshipGiftRecord({
    required this.id,
    required this.type,
    required this.createdAt,
  });

  final String id;
  final RelationshipGiftType type;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'createdAt': createdAt.toIso8601String(),
  };

  factory RelationshipGiftRecord.fromJson(Map<dynamic, dynamic> json) =>
      RelationshipGiftRecord(
        id: _text(json['id']),
        type: RelationshipGiftType.values.firstWhere(
          (value) => value.name == _text(json['type']),
          orElse: () => RelationshipGiftType.smallGift,
        ),
        createdAt:
            DateTime.tryParse(_text(json['createdAt'])) ?? DateTime.now(),
      );
}

class RelationshipGrowthProfile {
  const RelationshipGrowthProfile({
    required this.characterId,
    required this.totalExperience,
    required this.history,
    required this.gifts,
    required this.createdAt,
    required this.updatedAt,
  });

  final String characterId;
  final int totalExperience;
  final List<RelationshipGrowthEvent> history;
  final List<RelationshipGiftRecord> gifts;
  final DateTime createdAt;
  final DateTime updatedAt;

  int levelFor([
    RelationshipGrowthConfig config = RelationshipGrowthConfig.standard,
  ]) {
    var remaining = totalExperience;
    var level = 1;
    while (level < 100) {
      final required = config.experienceForNextLevel(level);
      if (remaining < required) break;
      remaining -= required;
      level++;
    }
    return level;
  }

  int currentExperienceFor([
    RelationshipGrowthConfig config = RelationshipGrowthConfig.standard,
  ]) {
    var remaining = totalExperience;
    for (var level = 1; level < levelFor(config); level++) {
      remaining -= config.experienceForNextLevel(level);
    }
    return remaining.clamp(0, 1 << 30);
  }

  int nextLevelExperienceFor([
    RelationshipGrowthConfig config = RelationshipGrowthConfig.standard,
  ]) => config.experienceForNextLevel(levelFor(config));

  String stageFor([
    RelationshipGrowthConfig config = RelationshipGrowthConfig.standard,
  ]) => config.stageFor(levelFor(config));

  RelationshipGrowthProfile copyWith({
    int? totalExperience,
    List<RelationshipGrowthEvent>? history,
    List<RelationshipGiftRecord>? gifts,
    DateTime? updatedAt,
  }) => RelationshipGrowthProfile(
    characterId: characterId,
    totalExperience: totalExperience ?? this.totalExperience,
    history: history ?? this.history,
    gifts: gifts ?? this.gifts,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'characterId': characterId,
    'totalExperience': totalExperience,
    'level': levelFor(),
    'currentExperience': currentExperienceFor(),
    'nextLevelExperience': nextLevelExperienceFor(),
    'currentStage': stageFor(),
    'history': history.map((item) => item.toJson()).toList(),
    'gifts': gifts.map((item) => item.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory RelationshipGrowthProfile.fromJson(Map<dynamic, dynamic> json) {
    final now = DateTime.now();
    final history = json['history'];
    final gifts = json['gifts'];
    return RelationshipGrowthProfile(
      characterId: _text(json['characterId']),
      totalExperience: _nonNegativeInt(json['totalExperience']),
      history: history is List
          ? history
                .whereType<Map>()
                .map(RelationshipGrowthEvent.fromJson)
                .where((item) => item.id.isNotEmpty)
                .toList()
          : const [],
      gifts: gifts is List
          ? gifts
                .whereType<Map>()
                .map(RelationshipGiftRecord.fromJson)
                .where((item) => item.id.isNotEmpty)
                .toList()
          : const [],
      createdAt: DateTime.tryParse(_text(json['createdAt'])) ?? now,
      updatedAt: DateTime.tryParse(_text(json['updatedAt'])) ?? now,
    );
  }
}

String _text(dynamic value) => value?.toString().trim() ?? '';

int _nonNegativeInt(dynamic value) =>
    (int.tryParse(value?.toString() ?? '') ?? 0).clamp(0, 1 << 30);
