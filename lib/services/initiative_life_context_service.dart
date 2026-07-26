import '../models/story_fragment.dart';
import 'life_moment_storage_service.dart';
import 'narrative_engine_service.dart';
import 'story_fragment_engine_service.dart';

class InitiativeLifeContext {
  const InitiativeLifeContext({
    required this.message,
    required this.momentId,
  });

  final String message;
  final String momentId;
}

class InitiativeLifeContextService {
  InitiativeLifeContextService({required this.characterId});

  final String characterId;

  Future<InitiativeLifeContext?> build({
    required DateTime now,
    required Set<String> excludedMomentIds,
  }) async {
    final items = await LifeMomentStorageService(
      characterId: characterId,
    ).loadItems();

    final earliest = now.subtract(const Duration(hours: 36));
    final available = items
        .where((item) => item.occurredAt.isAfter(earliest))
        .where((item) => !excludedMomentIds.contains(item.id))
        .toList();
    final fragments = const StoryFragmentEngineService().build(
      available,
      now: now,
      limit: 5,
    );
    if (fragments.isEmpty) return null;

    final seed = now.day + now.hour + now.minute ~/ 10;
    final candidateCount = fragments.length < 3 ? fragments.length : 3;
    final fragment = fragments[seed % candidateCount];
    final narrative = const NarrativeEngineService().render(
      fragment,
      perspective: NarrativePerspective.chat,
      now: now,
    );
    final core = _trimSentence(narrative.content, maxLength: 56);
    if (core.isEmpty) return null;

    final endings = <String>[
      '$core 刚才忽然想跟你说一声。',
      '$core 你今天有没有碰到什么有意思的事？',
      '$core 想到你大概会有话说。',
    ];
    return InitiativeLifeContext(
      message: endings[seed % endings.length],
      momentId: fragment.lifeMomentIds.first,
    );
  }

  String _trimSentence(String value, {required int maxLength}) {
    final clean = value
        .trim()
        .replaceAll(RegExp(r'[。！？!?]+$'), '');
    if (clean.length <= maxLength) return clean;
    return '${clean.substring(0, maxLength).trim()}…';
  }
}
