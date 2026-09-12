import 'dart:convert';
import 'dart:io';

import '../config/peilink_runtime.dart';
import '../models/event_memory.dart';
import '../models/group_memory_event.dart';
import '../models/memory_extraction_state.dart';
import '../platform/storage/platform_storage.dart';
import 'memory2_mutation_coordinator.dart';

typedef GroupMemoryFileProvider =
    Future<File> Function(String groupId, String fileName);

/// Group-scoped persistence for lightweight group memories.
///
/// The file format mirrors Memory 2.0 (`schemaVersion: 2`, `items`) and the
/// rows are serialized as [EventMemory], but the location is group scoped and
/// never touches `characters/<id>/**`. Character Memory 2.0, CharacterArchive
/// and CharacterUserProfile stay untouched.
class GroupMemoryStorageService {
  const GroupMemoryStorageService({
    required this.groupId,
    this.fileProvider,
    this.platformStorage,
  });

  static const int schemaVersion = 2;
  static const String eventsFileName = 'group_memories.json';
  static const String stateFileName = 'group_memory_state.json';
  static const int maximumStoredEvents = 200;

  final String groupId;
  final GroupMemoryFileProvider? fileProvider;
  final PlatformStorage? platformStorage;

  String get _safeGroupId => sanitizeGroupId(groupId);

  static String sanitizeGroupId(String value) {
    final normalized = value.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return normalized.isEmpty ? 'unnamed_group' : normalized;
  }

  String get storageKeyPrefix => 'group_chats/$_safeGroupId';

  Future<List<GroupMemoryEvent>> loadEvents() async {
    try {
      if (!await _exists(eventsFileName)) return const [];
      final raw = await _readText(eventsFileName);
      if (raw.trim().isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['schemaVersion'] != schemaVersion) {
        return const [];
      }
      final items = decoded['items'];
      if (items is! List) return const [];
      final events = <GroupMemoryEvent>[];
      for (final item in items.whereType<Map>()) {
        final parsed = GroupMemoryEvent.tryFromEventMemory(
          EventMemory.fromJson(item),
          fallbackGroupId: groupId,
        );
        // Cross-group rows in a mis-placed file are ignored, never adopted.
        if (parsed != null && parsed.groupId == groupId) events.add(parsed);
      }
      return events;
    } catch (_) {
      // Old or missing group memory data must never block reading a group.
      return const [];
    }
  }

  Future<void> saveEvents(List<GroupMemoryEvent> items) async {
    await _replaceTextSafely(
      eventsFileName,
      jsonEncode({
        'schemaVersion': schemaVersion,
        'items': items
            .where((item) => item.id.isNotEmpty && item.content.trim().isNotEmpty)
            .map((item) => item.toEventMemory().toJson())
            .toList(),
      }),
    );
  }

  /// Appends de-duplicated events and returns how many new rows were added.
  Future<int> appendEvents(
    List<GroupMemoryEvent> candidates, {
    DateTime? now,
  }) async {
    if (candidates.isEmpty) return 0;
    return Memory2MutationCoordinator.runExclusive(
      'group:$_safeGroupId',
      () async {
        // loadEvents() may return a const/immutable list (missing file, tolerant
        // read fallback). Always mutate a growable copy.
        final existing = List<GroupMemoryEvent>.from(await loadEvents());
        var added = 0;
        final time = now ?? DateTime.now();
        for (final candidate in candidates) {
          if (candidate.content.trim().isEmpty) continue;
          final index = existing.indexWhere(
            (item) => _sameEvent(item, candidate),
          );
          if (index >= 0) {
            final old = existing[index];
            final merged = <String>{
              ...old.sourceMessageIds,
              ...candidate.sourceMessageIds,
            }.toList();
            if (merged.length != old.sourceMessageIds.length) {
              existing[index] = old.copyWith(
                sourceMessageIds: merged,
                updatedAt: time,
              );
            }
            continue;
          }
          existing.add(candidate);
          added++;
        }
        await saveEvents(_trim(existing));
        return added;
      },
    );
  }

  Future<MemoryExtractionState> loadState() async {
    final fallback = MemoryExtractionState(characterId: groupId);
    try {
      if (!await _exists(stateFileName)) return fallback;
      final raw = await _readText(stateFileName);
      if (raw.trim().isEmpty) return fallback;
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['schemaVersion'] != schemaVersion) {
        return fallback;
      }
      final state = decoded['state'];
      return state is Map
          ? MemoryExtractionState.fromJson(state, characterId: groupId)
          : fallback;
    } catch (_) {
      return fallback;
    }
  }

  Future<void> saveState(MemoryExtractionState state) async {
    final scoped = MemoryExtractionState(
      characterId: groupId,
      explicitAttempts: state.explicitAttempts,
      lastProcessedMessageId: state.lastProcessedMessageId,
      lastProcessedAt: state.lastProcessedAt,
      lastSuccessfulExtractionAt: state.lastSuccessfulExtractionAt,
      lastFailureAt: state.lastFailureAt,
      lastFailedMessageId: state.lastFailedMessageId,
    );
    await _replaceTextSafely(
      stateFileName,
      jsonEncode({'schemaVersion': schemaVersion, 'state': scoped.toJson()}),
    );
  }

  List<GroupMemoryEvent> _trim(List<GroupMemoryEvent> items) {
    final result = List<GroupMemoryEvent>.from(items);
    if (result.length <= maximumStoredEvents) return result;
    final excess = result.length - maximumStoredEvents;
    var removed = 0;
    for (var index = 0; index < result.length && removed < excess; ) {
      if (result[index].isPinned) {
        index++;
        continue;
      }
      result.removeAt(index);
      removed++;
    }
    return result;
  }

  bool _sameEvent(GroupMemoryEvent first, GroupMemoryEvent second) =>
      (first.groupId == second.groupId) &&
      (first.sourceMessageIds.toSet().intersection(
                second.sourceMessageIds.toSet(),
              ).isNotEmpty ||
          _similarText(first.content, second.content));

  bool _similarText(String first, String second) {
    final a = _normalize(first);
    final b = _normalize(second);
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b || a.contains(b) || b.contains(a)) return true;
    final left = a.split('').toSet();
    final right = b.split('').toSet();
    final union = left.union(right).length;
    return union > 0 && left.intersection(right).length / union >= 0.82;
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(
        RegExp(r"[\s，。！？、：；~～“”‘’()（）\[\]【】《》_\-]+"),
        '',
      );

  Future<File> _file(String fileName) async {
    final provider = fileProvider;
    if (provider != null) return provider(groupId, fileName);
    final storage = platformStorage ?? await PeiLinkRuntime.storage();
    return File(storage.reference('$storageKeyPrefix/$fileName'));
  }

  Future<(PlatformStorage, String)> _location(String fileName) async => (
    platformStorage ?? await PeiLinkRuntime.storage(),
    '$storageKeyPrefix/$fileName',
  );

  Future<bool> _exists(String fileName) async {
    if (fileProvider != null) return (await _file(fileName)).exists();
    final (storage, key) = await _location(fileName);
    return storage.exists(key);
  }

  Future<String> _readText(String fileName) async {
    if (fileProvider != null) return (await _file(fileName)).readAsString();
    final (storage, key) = await _location(fileName);
    return storage.readText(key);
  }

  Future<void> _replaceTextSafely(String fileName, String value) async {
    if (fileProvider != null) {
      final file = await _file(fileName);
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(value, flush: true);
      await temporary.rename(file.path);
      return;
    }
    final (storage, key) = await _location(fileName);
    await storage.replaceTextSafely(key, value);
  }
}
