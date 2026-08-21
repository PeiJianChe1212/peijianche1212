import 'ai_character.dart';

enum LifeFeedSource { moment, echo, trace }

class LifeFeedEntry {
  const LifeFeedEntry({
    required this.character,
    required this.summary,
    required this.createdAt,
    required this.source,
    required this.sourceId,
    required this.dedupeKey,
    this.icon = '',
  });

  final AiCharacter character;
  final String summary;
  final DateTime createdAt;
  final LifeFeedSource source;
  final String sourceId;
  final String dedupeKey;
  final String icon;
}
