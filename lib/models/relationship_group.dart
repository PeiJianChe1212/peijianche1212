class RelationshipGroup {
  const RelationshipGroup({
    required this.id,
    required this.name,
    required this.emoji,
    this.characterIds = const [],
  });

  final String id;
  final String name;
  final String emoji;
  final List<String> characterIds;

  RelationshipGroup copyWith({
    String? name,
    String? emoji,
    List<String>? characterIds,
  }) => RelationshipGroup(
    id: id,
    name: name ?? this.name,
    emoji: emoji ?? this.emoji,
    characterIds: characterIds ?? this.characterIds,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'emoji': emoji,
    'characterIds': characterIds,
  };

  factory RelationshipGroup.fromJson(Map<dynamic, dynamic> json) =>
      RelationshipGroup(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        emoji: json['emoji']?.toString() ?? '✨',
        characterIds: (json['characterIds'] as List? ?? const [])
            .map((item) => item.toString())
            .toList(),
      );
}

class RelationshipGroupCollection {
  const RelationshipGroupCollection({
    this.groups = const [],
    this.favoriteCharacterIds = const [],
  });

  final List<RelationshipGroup> groups;
  final List<String> favoriteCharacterIds;

  Map<String, dynamic> toJson() => {
    'version': 1,
    'groups': groups.map((item) => item.toJson()).toList(),
    'favoriteCharacterIds': favoriteCharacterIds,
  };

  factory RelationshipGroupCollection.fromJson(Map<dynamic, dynamic> json) =>
      RelationshipGroupCollection(
        groups: (json['groups'] as List? ?? const [])
            .whereType<Map>()
            .map(RelationshipGroup.fromJson)
            .where((item) => item.id.isNotEmpty && item.name.isNotEmpty)
            .toList(),
        favoriteCharacterIds:
            (json['favoriteCharacterIds'] as List? ?? const [])
                .map((item) => item.toString())
                .toList(),
      );
}
