import '../models/ai_character.dart';
import '../models/echo_item.dart';
import '../models/life_feed_entry.dart';
import '../models/life_moment.dart';
import '../models/life_trace.dart';
import 'echo_storage_service.dart';
import 'life_moment_storage_service.dart';
import 'life_trace_service.dart';

typedef LifeMomentLoader =
    Future<List<LifeMomentCandidate>> Function(String id);
typedef EchoLoader = Future<List<EchoItem>> Function(String id);
typedef LifeTraceLoader = Future<List<LifeTrace>> Function(String id);

class LifeFeedService {
  LifeFeedService({
    LifeMomentLoader? loadMoments,
    EchoLoader? loadEchoes,
    LifeTraceLoader? loadTraces,
  }) : _loadMoments =
           loadMoments ??
           ((id) => LifeMomentStorageService(characterId: id).loadItems()),
       _loadEchoes =
           loadEchoes ??
           ((id) => EchoStorageService(characterId: id).loadItems()),
       _loadTraces =
           loadTraces ??
           ((id) => LifeTraceService(characterId: id).loadRecent(limit: 8));

  final LifeMomentLoader _loadMoments;
  final EchoLoader _loadEchoes;
  final LifeTraceLoader _loadTraces;

  Future<List<LifeFeedEntry>> load(
    List<AiCharacter> characters, {
    int limit = 5,
  }) async {
    final entries = <LifeFeedEntry>[];
    for (final character in characters) {
      final results = await Future.wait([
        _loadMoments(character.id),
        _loadEchoes(character.id),
        _loadTraces(character.id),
      ]);
      final moments = results[0] as List<LifeMomentCandidate>;
      final echoes = results[1] as List<EchoItem>;
      final traces = results[2] as List<LifeTrace>;

      // Echo 优先占用其 Life 来源 ID，同源 Moment 不再重复展示。
      for (final echo in echoes.take(6)) {
        final sourceId = echo.sourceLifeEventId.trim();
        entries.add(
          LifeFeedEntry(
            character: character,
            summary: echo.content.trim(),
            createdAt: echo.createdAt,
            source: LifeFeedSource.echo,
            sourceId: echo.id,
            dedupeKey: sourceId.isEmpty
                ? _legacyKey(character.id, 'echo', echo.createdAt)
                : '${character.id}|life|$sourceId',
            icon: '💬',
          ),
        );
      }
      for (final moment in moments.take(6)) {
        entries.add(
          LifeFeedEntry(
            character: character,
            summary: moment.event.trim(),
            createdAt: moment.occurredAt,
            source: LifeFeedSource.moment,
            sourceId: moment.id,
            dedupeKey: '${character.id}|life|${moment.id}',
            icon: '✨',
          ),
        );
      }
      for (final trace in traces.take(6)) {
        entries.add(
          LifeFeedEntry(
            character: character,
            summary: trace.title.trim(),
            createdAt: trace.occurredAt,
            source: LifeFeedSource.trace,
            sourceId: trace.id,
            dedupeKey: trace.id.isEmpty
                ? _legacyKey(character.id, trace.kind, trace.occurredAt)
                : '${character.id}|trace|${trace.id}',
            icon: trace.emoji,
          ),
        );
      }
    }

    entries.sort((a, b) {
      final time = b.createdAt.compareTo(a.createdAt);
      if (time != 0) return time;
      return _priority(a.source).compareTo(_priority(b.source));
    });
    final seen = <String>{};
    return entries
        .where((entry) => entry.summary.isNotEmpty && seen.add(entry.dedupeKey))
        .take(limit)
        .toList();
  }

  static int _priority(LifeFeedSource source) => switch (source) {
    LifeFeedSource.echo => 0,
    LifeFeedSource.moment => 1,
    LifeFeedSource.trace => 2,
  };

  static String _legacyKey(String characterId, String kind, DateTime time) =>
      '$characterId|$kind|${time.millisecondsSinceEpoch ~/ 60000}';
}
