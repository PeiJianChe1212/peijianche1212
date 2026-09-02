import '../models/legacy_memory_view.dart';
import '../models/memory_item.dart';
import 'legacy_memory_migration_service.dart';

typedef LegacyMemoryLoader = Future<List<MemoryItem>> Function();

class LegacyMemoryAdapter {
  LegacyMemoryAdapter({required this.characterId, this.loader});

  final String characterId;
  final LegacyMemoryLoader? loader;

  Future<List<LegacyMemoryView>> loadReadOnlyViews() async {
    final loader = this.loader;
    if (loader != null) {
      return (await loader()).map(mapItem).toList(growable: false);
    }
    try {
      final raw = await LegacyMemoryMigrationService(
        characterId: characterId,
      ).readRawLegacy();
      return raw
          .map(LegacyMemoryMigrationService.parseEntry)
          .whereType<LegacyMigrationEntry>()
          .map(
            (e) => LegacyMemoryView(
              id: 'legacy_${e.id}',
              characterId: characterId,
              legacySourceId: e.id,
              kind: e.kind,
              content: e.content,
              category: e.category,
              createdAt: e.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
              isPinned: e.pinned,
              legacyArchived: e.archived,
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  LegacyMemoryView mapItem(MemoryItem item) => LegacyMemoryView(
    id: 'legacy_${item.id}',
    characterId: characterId,
    legacySourceId: item.id,
    kind: _kindFor(item.category),
    content: item.content,
    category: item.category,
    createdAt: item.createdAt,
    isPinned: item.isPinned,
    legacyArchived: item.isArchived,
  );

  LegacyMemoryKind _kindFor(String category) {
    return switch (category.trim()) {
      '经历过的事' || '共同纪念' => LegacyMemoryKind.event,
      '关于我' ||
      '关于念念' ||
      '兴趣偏好' ||
      '生活习惯' ||
      '害怕与禁忌' ||
      '重要关系' => LegacyMemoryKind.user,
      _ => LegacyMemoryKind.legacyUnclassified,
    };
  }
}
