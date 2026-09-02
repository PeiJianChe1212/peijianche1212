import 'dart:convert';
import 'dart:io';

import '../models/event_memory.dart';
import '../models/user_memory.dart';
import '../models/memory_source_type.dart';
import '../models/legacy_memory_view.dart';
import 'character_scope_service.dart';
import 'memory2_storage_service.dart';
import 'memory2_mutation_coordinator.dart';

String normalizeLegacyMemory(String text) =>
    text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

class LegacyMigrationEntry {
  const LegacyMigrationEntry({
    required this.id,
    required this.content,
    required this.category,
    required this.kind,
    this.createdAt,
    this.pinned = false,
    this.archived = false,
  });
  final String id, content, category;
  final LegacyMemoryKind kind;
  final DateTime? createdAt;
  final bool pinned, archived;
}

class LegacyMigrationPreview {
  const LegacyMigrationPreview({
    required this.events,
    required this.users,
    required this.duplicates,
    required this.unclassified,
    required this.archived,
    required this.invalid,
    required this.revision,
  });
  final int events, users, duplicates, unclassified, archived, invalid;
  final String revision;
  int get transferable => events + users;
}

class LegacyMigrationResult {
  const LegacyMigrationResult({required this.success, this.error});
  final bool success;
  final String? error;
}

/// Explicit-only migration. No caller should invoke execute during load/chat.
class LegacyMemoryMigrationService {
  LegacyMemoryMigrationService({
    required this.characterId,
    Memory2StorageService? storage,
    this.fileProvider,
  }) : storage =
           storage ??
           Memory2StorageService(
             characterId: characterId,
             fileProvider: fileProvider,
           );
  final String characterId;
  final Memory2StorageService storage;
  final Memory2FileProvider? fileProvider;
  static const ledgerFile = 'legacy_memory_migration.json';

  Future<File> _file(String name) => fileProvider != null
      ? fileProvider!(characterId, name)
      : CharacterScopeService(characterId).dataFile(name);

  static LegacyMemoryKind classify(String category) =>
      switch (category.trim()) {
        '经历过的事' || '共同纪念' => LegacyMemoryKind.event,
        '关于我' ||
        '关于念念' ||
        '兴趣偏好' ||
        '生活习惯' ||
        '害怕与禁忌' ||
        '重要关系' => LegacyMemoryKind.user,
        _ => LegacyMemoryKind.legacyUnclassified,
      };

  Future<List<dynamic>> readRawLegacy() async {
    final file = await _file('memories.json');
    if (!await file.exists()) return [];
    final value = jsonDecode(await file.readAsString());
    if (value is! List) throw const FormatException('旧记忆文件格式损坏');
    return value;
  }

  static LegacyMigrationEntry? parseEntry(dynamic raw) {
    if (raw is! Map ||
        raw['content'] is! String ||
        (raw['content'] as String).trim().isEmpty) {
      return null;
    }
    final content = raw['content'] as String;
    final category = raw['category'] is String ? raw['category'] as String : '';
    final id = raw['id'] is String && (raw['id'] as String).trim().isNotEmpty
        ? raw['id'] as String
        : 'missing_${base64Url.encode(utf8.encode(jsonEncode([category, content])))}';
    return LegacyMigrationEntry(
      id: id,
      content: content,
      category: category,
      kind: classify(category),
      createdAt: DateTime.tryParse('${raw['createdAt'] ?? ''}'),
      pinned: raw['isPinned'] == true,
      archived: raw['isArchived'] == true,
    );
  }

  Future<LegacyMigrationPreview> preview() async => (await _plan()).preview;

  Future<_MigrationPlan> _plan() async {
    final raw = await readRawLegacy();
    final events = await storage.loadEventMemoriesStrict();
    final users = await storage.loadUserMemoriesStrict();
    final links = await _readLedger();
    final eventSources = {
      for (final e in events)
        if (e.legacySourceId != null) e.legacySourceId!: e.id,
    };
    final userSources = {
      for (final e in users)
        if (e.legacySourceId != null) e.legacySourceId!: e.id,
    };
    final eventContents = {
      for (final e in events) normalizeLegacyMemory(e.content): e.id,
    };
    final userContents = <String, String>{};
    for (final u in users) {
      userContents[normalizeLegacyMemory(u.displayText)] = u.id;
      if (u.key.trim().isEmpty) {
        userContents[normalizeLegacyMemory(u.value)] = u.id;
      }
    }
    final signatures = <String, Set<String>>{};
    for (final entry in raw.map(parseEntry).whereType<LegacyMigrationEntry>()) {
      signatures
          .putIfAbsent(entry.id, () => {})
          .add('${entry.kind.name}:${normalizeLegacyMemory(entry.content)}');
    }
    final eventIds = events.map((e) => e.id).toSet();
    final userIds = users.map((u) => u.id).toSet();
    final newEntries = <LegacyMigrationEntry>[];
    var duplicate = 0, unknown = 0, archived = 0, invalid = 0;
    for (final item in raw) {
      final entry = parseEntry(item);
      if (entry == null || signatures[entry.id]!.length > 1) {
        invalid++;
        continue;
      }
      if (entry.archived) {
        archived++;
        continue;
      }
      if (entry.kind == LegacyMemoryKind.legacyUnclassified) {
        unknown++;
        continue;
      }
      final isEvent = entry.kind == LegacyMemoryKind.event;
      final sources = isEvent ? eventSources : userSources;
      final contents = isEvent ? eventContents : userContents;
      final priorLink = links[entry.id];
      final linkedId =
          priorLink?['kind'] == (isEvent ? 'event' : 'user') &&
              (isEvent
                  ? events.any((e) => e.id == priorLink?['id'])
                  : users.any((u) => u.id == priorLink?['id']))
          ? priorLink!['id']
          : null;
      final target =
          sources[entry.id] ??
          linkedId ??
          contents[normalizeLegacyMemory(entry.content)];
      var targetId =
          target ??
          'legacy_${isEvent ? 'event' : 'user'}_${base64Url.encode(utf8.encode(entry.id))}';
      final ids = isEvent ? eventIds : userIds;
      if (target == null) {
        final base = targetId;
        var suffix = 2;
        while (ids.contains(targetId)) {
          targetId = '${base}_${suffix++}';
        }
        ids.add(targetId);
      }
      links[entry.id] = {'kind': isEvent ? 'event' : 'user', 'id': targetId};
      if (target != null) {
        duplicate++;
      } else {
        newEntries.add(entry);
      }
      sources[entry.id] = targetId;
      contents[normalizeLegacyMemory(entry.content)] = targetId;
    }
    return _MigrationPlan(
      events,
      users,
      newEntries,
      links,
      LegacyMigrationPreview(
        events: newEntries
            .where((e) => e.kind == LegacyMemoryKind.event)
            .length,
        users: newEntries.where((e) => e.kind == LegacyMemoryKind.user).length,
        duplicates: duplicate,
        unclassified: unknown,
        archived: archived,
        invalid: invalid,
        revision: jsonEncode([
          raw,
          events.map((e) => e.toJson()).toList(),
          users.map((u) => u.toJson()).toList(),
        ]),
      ),
    );
  }

  Future<LegacyMigrationResult> execute(LegacyMigrationPreview confirmed) =>
      Memory2MutationCoordinator.runExclusive(characterId, () async {
        try {
          final plan = await _plan();
          if (plan.preview.revision != confirmed.revision) {
            return const LegacyMigrationResult(
              success: false,
              error: '记忆已发生变化，请重新预览。',
            );
          }
          final now = DateTime.now();
          for (final entry in plan.entries) {
            final id = plan.links[entry.id]!['id']!;
            if (entry.kind == LegacyMemoryKind.event) {
              plan.events.add(
                EventMemory(
                  id: id,
                  characterId: characterId,
                  content: entry.content,
                  createdAt: entry.createdAt ?? now,
                  updatedAt: now,
                  isPinned: entry.pinned,
                  sourceType: MemorySourceType.legacy,
                  legacySourceId: entry.id,
                ),
              );
            } else {
              plan.users.add(
                UserMemory(
                  id: id,
                  characterId: characterId,
                  key: '',
                  value: entry.content,
                  createdAt: entry.createdAt ?? now,
                  updatedAt: now,
                  isPinned: entry.pinned,
                  sourceType: MemorySourceType.legacy,
                  legacySourceId: entry.id,
                ),
              );
            }
          }
          if (plan.entries.any((e) => e.kind == LegacyMemoryKind.event)) {
            await storage.saveEventMemories(plan.events);
          }
          if (plan.entries.any((e) => e.kind == LegacyMemoryKind.user)) {
            await storage.saveUserMemories(plan.users);
          }
          final file = await _file(ledgerFile);
          await file.parent.create(recursive: true);
          final temporary = File('${file.path}.tmp');
          await temporary.writeAsString(
            jsonEncode({'version': 1, 'links': plan.links}),
            flush: true,
          );
          await temporary.rename(file.path);
          return const LegacyMigrationResult(success: true);
        } catch (_) {
          return const LegacyMigrationResult(
            success: false,
            error: '整理未全部完成，旧数据仍保留。请重新预览后重试。',
          );
        }
      });

  Future<Map<String, Map<String, String>>> _readLedger() async {
    final file = await _file(ledgerFile);
    if (!await file.exists()) return {};
    final raw = jsonDecode(await file.readAsString());
    if (raw is! Map || raw['version'] != 1 || raw['links'] is! Map) {
      throw const FormatException('迁移记录损坏');
    }
    for (final entry in (raw['links'] as Map).entries) {
      final value = entry.value;
      if (entry.key is! String ||
          value is! Map ||
          value['id'] is! String ||
          !const ['event', 'user'].contains(value['kind'])) {
        throw const FormatException('迁移来源关联损坏');
      }
    }
    return (raw['links'] as Map).map(
      (key, value) =>
          MapEntry(key.toString(), Map<String, String>.from(value as Map)),
    );
  }

  Future<Set<String>> migratedSourceIds(
    List<EventMemory> events,
    List<UserMemory> users,
  ) async {
    final ids = <String>{
      ...events.map((e) => e.legacySourceId).whereType<String>(),
      ...users.map((u) => u.legacySourceId).whereType<String>(),
    };
    try {
      final links = await _readLedger();
      for (final entry in links.entries) {
        final target = entry.value;
        if (target['kind'] == 'event'
            ? events.any((e) => e.id == target['id'])
            : users.any((u) => u.id == target['id'])) {
          ids.add(entry.key);
        }
      }
    } catch (_) {
      // A damaged migration journal must not interrupt ordinary chat.
    }
    return ids;
  }

  Future<Map<String, Map<String, String>>> existingSourceLinks(
    List<EventMemory> events,
    List<UserMemory> users,
  ) async {
    final links = await _readLedger();
    links.removeWhere(
      (_, target) => target['kind'] == 'event'
          ? !events.any((e) => e.id == target['id'])
          : target['kind'] != 'user' || !users.any((u) => u.id == target['id']),
    );
    for (final e in events) {
      if (e.legacySourceId != null) {
        links[e.legacySourceId!] = {'kind': 'event', 'id': e.id};
      }
    }
    for (final u in users) {
      if (u.legacySourceId != null) {
        links[u.legacySourceId!] = {'kind': 'user', 'id': u.id};
      }
    }
    return links;
  }
}

class _MigrationPlan {
  _MigrationPlan(
    this.events,
    this.users,
    this.entries,
    this.links,
    this.preview,
  );
  final List<EventMemory> events;
  final List<UserMemory> users;
  final List<LegacyMigrationEntry> entries;
  final Map<String, Map<String, String>> links;
  final LegacyMigrationPreview preview;
}
