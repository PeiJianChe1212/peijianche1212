class StoryFragment {
  const StoryFragment({
    required this.id,
    required this.title,
    required this.summary,
    required this.startedAt,
    required this.endedAt,
    required this.lifeMomentIds,
    this.scene = '',
    this.feeling = '',
    this.causeNodeIds = const [],
    this.worldEventIds = const [],
    this.relatedCharacterNames = const [],
  });

  final String id;
  final String title;
  final String summary;
  final DateTime startedAt;
  final DateTime endedAt;
  final List<String> lifeMomentIds;
  final String scene;
  final String feeling;
  final List<String> causeNodeIds;
  final List<String> worldEventIds;
  final List<String> relatedCharacterNames;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'summary': summary,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt.toIso8601String(),
        'lifeMomentIds': lifeMomentIds,
        'scene': scene,
        'feeling': feeling,
        'causeNodeIds': causeNodeIds,
        'worldEventIds': worldEventIds,
        'relatedCharacterNames': relatedCharacterNames,
      };

  factory StoryFragment.fromJson(Map<dynamic, dynamic> json) {
    return StoryFragment(
      id: json['id']?.toString().trim() ?? '',
      title: json['title']?.toString().trim() ?? '',
      summary: json['summary']?.toString().trim() ?? '',
      startedAt: DateTime.tryParse(json['startedAt']?.toString() ?? '') ??
          DateTime.now(),
      endedAt: DateTime.tryParse(json['endedAt']?.toString() ?? '') ??
          DateTime.now(),
      lifeMomentIds: _strings(json['lifeMomentIds']),
      scene: json['scene']?.toString().trim() ?? '',
      feeling: json['feeling']?.toString().trim() ?? '',
      causeNodeIds: _strings(json['causeNodeIds']),
      worldEventIds: _strings(json['worldEventIds']),
      relatedCharacterNames: _strings(json['relatedCharacterNames']),
    );
  }

  static List<String> _strings(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
  }
}

enum NarrativePerspective { chat, echo, memory, summary }

class NarrativeSnapshot {
  const NarrativeSnapshot({
    required this.fragmentId,
    required this.perspective,
    required this.content,
    required this.createdAt,
    required this.lifeMomentIds,
    this.causeNodeIds = const [],
  });

  final String fragmentId;
  final NarrativePerspective perspective;
  final String content;
  final DateTime createdAt;
  final List<String> lifeMomentIds;
  final List<String> causeNodeIds;
}
