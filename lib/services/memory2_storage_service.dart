import 'dart:convert';
import 'dart:io';

import '../models/event_memory.dart';
import '../models/memory_summary.dart';
import '../models/user_memory.dart';
import '../models/memory_source_type.dart';
import '../platform/storage/platform_storage.dart';
import 'character_scope_service.dart';
import 'memory2_mutation_coordinator.dart';

typedef Memory2FileProvider =
    Future<File> Function(String characterId, String fileName);

/// Character-scoped persistence for the Memory 2.0 data foundation.
///
/// This service never reads or writes legacy memories.json, pending memories,
/// CharacterArchive, CharacterUserProfile, or .pei packages.
class Memory2StorageService {
  const Memory2StorageService({
    required this.characterId,
    this.fileProvider,
    this.platformStorage,
  });

  static const int schemaVersion = 2;
  static const String eventFileName = 'event_memories.json';
  static const String userFileName = 'user_memories.json';
  static const String summaryFileName = 'memory_summary.json';

  final String characterId;
  final Memory2FileProvider? fileProvider;
  final PlatformStorage? platformStorage;

  Future<List<EventMemory>> loadEventMemoriesStrict() async =>
      (await _loadItems(
        eventFileName,
        strict: true,
      )).map((e) => _scopeEvent(EventMemory.fromJson(e as Map))).toList();
  Future<List<UserMemory>> loadUserMemoriesStrict() async => (await _loadItems(
    userFileName,
    strict: true,
  )).map((e) => _scopeUser(UserMemory.fromJson(e as Map))).toList();

  Future<List<EventMemory>> loadEventMemories() async {
    final items = await _loadItems(eventFileName);
    return items
        .whereType<Map>()
        .map(EventMemory.fromJson)
        .where((item) => item.id.isNotEmpty && item.content.isNotEmpty)
        .map(_scopeEvent)
        .toList();
  }

  Future<void> saveEventMemories(List<EventMemory> items) async {
    await loadEventMemoriesStrict();
    await _saveItems(
      eventFileName,
      items.map(_scopeEvent).map((item) => item.toJson()).toList(),
    );
  }

  Future<void> upsertEventMemory(EventMemory memory) async {
    await Memory2MutationCoordinator.runExclusive(characterId, () async {
      final items = await loadEventMemories();
      final scoped = _scopeEvent(memory);
      final index = items.indexWhere((item) => item.id == scoped.id);
      if (index >= 0) {
        items[index] = scoped;
      } else {
        items.add(scoped);
      }
      await saveEventMemories(items);
    });
  }

  Future<void> deleteEventMemory(String id) async {
    await Memory2MutationCoordinator.runExclusive(characterId, () async {
      final items = await loadEventMemories();
      items.removeWhere((item) => item.id == id);
      await saveEventMemories(items);
    });
  }

  Future<List<UserMemory>> loadUserMemories() async {
    final items = await _loadItems(userFileName);
    return items
        .whereType<Map>()
        .map(UserMemory.fromJson)
        .where((item) => item.id.isNotEmpty && item.displayText.isNotEmpty)
        .map(_scopeUser)
        .toList();
  }

  Future<void> saveUserMemories(List<UserMemory> items) async {
    await loadUserMemoriesStrict();
    await _saveItems(
      userFileName,
      items.map(_scopeUser).map((item) => item.toJson()).toList(),
    );
  }

  Future<void> upsertUserMemory(UserMemory memory) async {
    await Memory2MutationCoordinator.runExclusive(characterId, () async {
      final items = await loadUserMemories();
      final scoped = _scopeUser(memory);
      final index = items.indexWhere((item) => item.id == scoped.id);
      if (index >= 0) {
        items[index] = scoped;
      } else {
        items.add(scoped);
      }
      await saveUserMemories(items);
    });
  }

  Future<void> deleteUserMemory(String id) async {
    await Memory2MutationCoordinator.runExclusive(characterId, () async {
      final items = await loadUserMemories();
      items.removeWhere((item) => item.id == id);
      await saveUserMemories(items);
    });
  }

  Future<MemorySummary> loadMemorySummary() =>
      _loadMemorySummary(strict: false);

  Future<MemorySummary> loadMemorySummaryStrict() =>
      _loadMemorySummary(strict: true);

  Future<MemorySummary> _loadMemorySummary({required bool strict}) async {
    final fallback = MemorySummary(characterId: characterId);
    try {
      if (!await _exists(summaryFileName)) return fallback;
      final raw = await _readText(summaryFileName);
      if (raw.trim().isEmpty) {
        if (strict) throw const FormatException('Empty summary file');
        return fallback;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['schemaVersion'] != schemaVersion) {
        if (strict) throw const FormatException('Invalid summary schema');
        return fallback;
      }
      final summary = decoded['summary'];
      if (summary is! Map) {
        if (strict) throw const FormatException('Invalid summary');
        return fallback;
      }
      if (strict &&
          (summary['generatedText'] is! String ||
              summary['userEditedText'] is! String ||
              summary['sourceRevision'] is! int ||
              summary['sourceRevision'] < 0 ||
              ['generatedAt', 'editedAt'].any(
                (key) =>
                    summary[key] != null &&
                    (summary[key] is! String ||
                        DateTime.tryParse(summary[key]) == null),
              ))) {
        throw const FormatException('Invalid summary fields');
      }
      final parsed = MemorySummary.fromJson(summary);
      return MemorySummary(
        characterId: characterId,
        generatedText: parsed.generatedText,
        userEditedText: parsed.userEditedText,
        generatedAt: parsed.generatedAt,
        editedAt: parsed.editedAt,
        sourceRevision: parsed.sourceRevision,
      );
    } catch (_) {
      if (strict) rethrow;
      return fallback;
    }
  }

  Future<void> saveMemorySummary(MemorySummary summary) async {
    await loadMemorySummaryStrict();
    final scoped = MemorySummary(
      characterId: characterId,
      generatedText: summary.generatedText,
      userEditedText: summary.userEditedText,
      generatedAt: summary.generatedAt,
      editedAt: summary.editedAt,
      sourceRevision: summary.sourceRevision,
    );
    await _replaceTextSafely(
      summaryFileName,
      jsonEncode({'schemaVersion': schemaVersion, 'summary': scoped.toJson()}),
    );
  }

  Future<List<dynamic>> _loadItems(
    String fileName, {
    bool strict = false,
  }) async {
    try {
      if (!await _exists(fileName)) return const [];
      final raw = await _readText(fileName);
      if (raw.trim().isEmpty) {
        if (strict) throw const FormatException('Empty Memory2 file');
        return const [];
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['schemaVersion'] != schemaVersion) {
        if (strict) throw const FormatException('Invalid Memory2 schema');
        return const [];
      }
      final items = decoded['items'];
      if (strict && (items is! List || items.any((e) => e is! Map))) {
        throw const FormatException('Invalid Memory2 items');
      }
      if (strict) {
        _validateStrictItems(items as List, fileName == eventFileName);
      }
      return items is List ? items : const [];
    } catch (_) {
      if (strict) rethrow;
      return const [];
    }
  }

  // Explicit migrations must fail closed instead of rewriting malformed rows
  // through the normal, deliberately tolerant runtime loaders.
  void _validateStrictItems(List items, bool event) {
    final ids = <String>{};
    for (final raw in items) {
      final m = raw as Map;
      bool date(String key, {bool optional = false}) =>
          optional && m[key] == null ||
          m[key] is String && DateTime.tryParse(m[key]) != null;
      bool strings(String key) =>
          m[key] is List && (m[key] as List).every((e) => e is String);
      if (m['id'] is! String ||
          (m['id'] as String).trim().isEmpty ||
          !ids.add(m['id']) ||
          !date('createdAt') ||
          !date('updatedAt') ||
          m['isPinned'] is! bool ||
          !strings('sourceMessageIds') ||
          !MemorySourceType.values.any((e) => e.name == m['sourceType']) ||
          m['legacySourceId'] != null && m['legacySourceId'] is! String) {
        throw const FormatException('Invalid Memory2 row');
      }
      if (event) {
        if (m['content'] is! String ||
            (m['content'] as String).trim().isEmpty ||
            !date('occurredAt', optional: true) ||
            !date('lastRecalledAt', optional: true) ||
            m['recallCount'] is! int ||
            m['recallCount'] < 0 ||
            !EventMemoryStatus.values.any((e) => e.name == m['status']) ||
            m['metadata'] != null && m['metadata'] is! Map) {
          throw const FormatException('Invalid EventMemory row');
        }
      } else if (m['key'] is! String ||
          m['value'] is! String ||
          '${m['key']}${m['value']}'.trim().isEmpty ||
          m['userConfirmed'] is! bool ||
          !strings('mergedFromIds') ||
          m['supersededById'] != null && m['supersededById'] is! String ||
          !UserMemoryStatus.values.any((e) => e.name == m['status'])) {
        throw const FormatException('Invalid UserMemory row');
      }
    }
  }

  Future<void> _saveItems(
    String fileName,
    List<Map<String, dynamic>> items,
  ) async {
    await _replaceTextSafely(
      fileName,
      jsonEncode({'schemaVersion': schemaVersion, 'items': items}),
    );
  }

  Future<(PlatformStorage, String)> _storageLocation(String fileName) async {
    final scope = CharacterScopeService(characterId);
    return (
      platformStorage ?? await scope.storage(),
      await scope.dataKey(fileName),
    );
  }

  Future<bool> _exists(String fileName) async {
    final provider = fileProvider;
    if (provider != null)
      return (await provider(characterId, fileName)).exists();
    final (storage, key) = await _storageLocation(fileName);
    return storage.exists(key);
  }

  Future<String> _readText(String fileName) async {
    final provider = fileProvider;
    if (provider != null)
      return (await provider(characterId, fileName)).readAsString();
    final (storage, key) = await _storageLocation(fileName);
    return storage.readText(key);
  }

  Future<void> _replaceTextSafely(String fileName, String value) async {
    final provider = fileProvider;
    if (provider != null) {
      final file = await provider(characterId, fileName);
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(value, flush: true);
      await temporary.rename(file.path);
      return;
    }
    final (storage, key) = await _storageLocation(fileName);
    await storage.replaceTextSafely(key, value);
  }

  EventMemory _scopeEvent(EventMemory item) => EventMemory(
    id: item.id,
    characterId: characterId,
    content: item.content,
    occurredAt: item.occurredAt,
    createdAt: item.createdAt,
    updatedAt: item.updatedAt,
    sourceMessageIds: item.sourceMessageIds,
    status: item.status,
    lastRecalledAt: item.lastRecalledAt,
    recallCount: item.recallCount,
    isPinned: item.isPinned,
    sourceType: item.sourceType,
    legacySourceId: item.legacySourceId,
    metadata: item.metadata,
  );

  UserMemory _scopeUser(UserMemory item) => UserMemory(
    id: item.id,
    characterId: characterId,
    key: item.key,
    value: item.value,
    createdAt: item.createdAt,
    updatedAt: item.updatedAt,
    sourceMessageIds: item.sourceMessageIds,
    status: item.status,
    supersededById: item.supersededById,
    mergedFromIds: item.mergedFromIds,
    isPinned: item.isPinned,
    userConfirmed: item.userConfirmed,
    sourceType: item.sourceType,
    legacySourceId: item.legacySourceId,
  );
}
