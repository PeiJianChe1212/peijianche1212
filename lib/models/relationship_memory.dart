class RelationshipMemory {
  const RelationshipMemory({
    required this.id,
    required this.characterIdA,
    required this.characterIdB,
    required this.summary,
    required this.recentMemories,
    required this.sharedPatterns,
    required this.generatedFromExperienceCount,
    required this.updatedAt,
    this.familiarity = 0,
    this.trust = 0,
    this.cooperation = 0,
    this.respect = 0,
    this.ease = 0,
  });

  final String id;
  final String characterIdA;
  final String characterIdB;
  final String summary;
  final List<String> recentMemories;
  final List<String> sharedPatterns;
  final int generatedFromExperienceCount;
  final DateTime updatedAt;

  /// 仅供底层判断使用，不直接展示给用户。
  final int familiarity;
  final int trust;
  final int cooperation;
  final int respect;
  final int ease;

  bool containsPair(String firstId, String secondId) =>
      (characterIdA == firstId && characterIdB == secondId) ||
      (characterIdA == secondId && characterIdB == firstId);

  Map<String, dynamic> toJson() => {
        'id': id,
        'characterIdA': characterIdA,
        'characterIdB': characterIdB,
        'summary': summary,
        'recentMemories': recentMemories,
        'sharedPatterns': sharedPatterns,
        'generatedFromExperienceCount': generatedFromExperienceCount,
        'updatedAt': updatedAt.toIso8601String(),
        'familiarity': familiarity,
        'trust': trust,
        'cooperation': cooperation,
        'respect': respect,
        'ease': ease,
      };

  factory RelationshipMemory.fromJson(Map<dynamic, dynamic> json) {
    final firstId = _text(json['characterIdA']);
    final secondId = _text(json['characterIdB']);
    return RelationshipMemory(
      id: _text(json['id']).isEmpty
          ? buildId(firstId, secondId)
          : _text(json['id']),
      characterIdA: firstId,
      characterIdB: secondId,
      summary: _text(json['summary']),
      recentMemories: _stringList(json['recentMemories']),
      sharedPatterns: _stringList(json['sharedPatterns']),
      generatedFromExperienceCount:
          int.tryParse(json['generatedFromExperienceCount']?.toString() ?? '') ?? 0,
      updatedAt: DateTime.tryParse(_text(json['updatedAt'])) ?? DateTime.now(),
      familiarity: _score(json['familiarity']),
      trust: _score(json['trust']),
      cooperation: _score(json['cooperation']),
      respect: _score(json['respect']),
      ease: _score(json['ease']),
    );
  }

  static String buildId(String firstId, String secondId) {
    final ids = [firstId.trim(), secondId.trim()]..sort();
    return 'relationship_memory_${ids[0]}__${ids[1]}';
  }

  static String _text(dynamic value) => value?.toString().trim() ?? '';

  static int _score(dynamic value) {
    final parsed = value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '');
    return (parsed ?? 0).clamp(0, 100).toInt();
  }

  static List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map(_text)
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
  }
}
