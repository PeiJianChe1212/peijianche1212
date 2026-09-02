import 'dart:convert';
import 'dart:io';

import '../models/event_memory.dart';
import '../models/user_memory.dart';
import '../models/legacy_memory_view.dart';
import '../models/memory_source_type.dart';
import 'legacy_memory_migration_service.dart';
import 'memory2_storage_service.dart';
import 'memory2_mutation_coordinator.dart';
import '../models/pending_memory.dart';
import 'character_scope_service.dart';
import 'memory_storage_service.dart';

class MemoryReviewService {
  MemoryReviewService({String? characterId})
    : _characterId = characterId,
      _memoryStorage = MemoryStorageService(characterId: characterId);

  final String? _characterId;
  final MemoryStorageService _memoryStorage;

  Future<File> _pendingFile() {
    return CharacterScopeService(_characterId).dataFile(
      'pending_memories.json',
      legacyDefaultFileName: 'pending_memories.json',
    );
  }

  Future<List<PendingMemory>> loadItems() async {
    final file = await _pendingFile();
    if (!await file.exists()) return [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map(PendingMemory.fromJson)
          .where((item) => item.content.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveItems(List<PendingMemory> items) async {
    final file = await _pendingFile();
    await file.writeAsString(
      jsonEncode(items.map((item) => item.toJson()).toList()),
      flush: true,
    );
  }

  Future<int> addCandidates(List<PendingMemory> candidates) async {
    final pending = await loadItems();
    final memories = await _memoryStorage.loadItems();
    final known = <String>{
      ...pending.map((item) => _normalize(item.content)),
      ...memories.map((item) => _normalize(item.content)),
    };
    var added = 0;
    for (final candidate in candidates) {
      final key = _normalize(candidate.content);
      if (key.isEmpty || known.contains(key)) continue;
      pending.add(candidate);
      known.add(key);
      added++;
    }
    await saveItems(pending);
    return added;
  }

  Future<void> update(PendingMemory item) async {
    final items = await loadItems();
    final index = items.indexWhere((candidate) => candidate.id == item.id);
    if (index < 0) return;
    items[index] = item;
    await saveItems(items);
  }

  Future<void> reject(String id) async {
    final items = await loadItems();
    items.removeWhere((item) => item.id == id);
    await saveItems(items);
  }

  Future<void> approve(PendingMemory item) async {
    final kind = LegacyMemoryMigrationService.classify(item.category);
    if (kind == LegacyMemoryKind.legacyUnclassified ||
        item.content.trim().isEmpty) {
      throw StateError('请先编辑并选择明确的经历或用户资料分类。');
    }
    final characterId = await CharacterScopeService(
      _characterId,
    ).resolveCharacterId();
    await Memory2MutationCoordinator.runExclusive(characterId, () async {
      final storage = Memory2StorageService(characterId: characterId);
      final source = 'pending:${item.id}';
      final id = 'legacy_pending_${base64Url.encode(utf8.encode(item.id))}';
      final now = DateTime.now();
      if (kind == LegacyMemoryKind.event) {
        final items = await storage.loadEventMemoriesStrict();
        if (!items.any(
          (e) =>
              e.id == id ||
              normalizeLegacyMemory(e.content) ==
                  normalizeLegacyMemory(item.content),
        )) {
          items.add(
            EventMemory(
              id: id,
              characterId: characterId,
              content: item.content,
              createdAt: item.createdAt,
              updatedAt: now,
              sourceType: MemorySourceType.legacy,
              legacySourceId: source,
            ),
          );
          await storage.saveEventMemories(items);
        }
      } else {
        final items = await storage.loadUserMemoriesStrict();
        if (!items.any(
          (u) =>
              u.id == id ||
              normalizeLegacyMemory(u.displayText) ==
                  normalizeLegacyMemory(item.content),
        )) {
          items.add(
            UserMemory(
              id: id,
              characterId: characterId,
              key: '',
              value: item.content,
              createdAt: item.createdAt,
              updatedAt: now,
              userConfirmed: true,
              sourceType: MemorySourceType.legacy,
              legacySourceId: source,
            ),
          );
          await storage.saveUserMemories(items);
        }
      }
      await reject(item.id);
    });
  }

  String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[\s，。！？、,.!?]'), '');
}
