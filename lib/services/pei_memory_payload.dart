import 'dart:convert';
import '../models/event_memory.dart';
import '../models/user_memory.dart';
import '../models/memory_summary.dart';
import '../models/memory_source_type.dart';
import 'character_scope_service.dart';
import 'legacy_memory_migration_service.dart';

/// Validated allowlisted portable memory only; never runtime/provider data.
class PeiMemoryPayload {
  PeiMemoryPayload._(this.legacy, this.events, this.users, this.summary);
  final List<Map<String, dynamic>> legacy;
  final List<EventMemory> events;
  final List<UserMemory> users;
  final MemorySummary summary;

  static Future<PeiMemoryPayload> load(String id) async {
    Future<dynamic> read(String name, dynamic fallback) async {
      final file = await CharacterScopeService(id).dataFile(name);
      return await file.exists()
          ? jsonDecode(await file.readAsString())
          : fallback;
    }

    final legacy = await read('memories.json', []);
    final events = await read('event_memories.json', {
      'schemaVersion': 2,
      'items': [],
    });
    final users = await read('user_memories.json', {
      'schemaVersion': 2,
      'items': [],
    });
    final summary = await read('memory_summary.json', {
      'schemaVersion': 2,
      'summary': MemorySummary(characterId: id).toJson(),
    });
    for (final value in [events, users, summary]) {
      if (value is! Map || value['schemaVersion'] != 2) {
        throw const FormatException('Invalid memory schema');
      }
    }
    final payload = parse({
      'legacy': legacy,
      'events': events['items'],
      'users': users['items'],
      'summary': summary['summary'],
    });
    // Portable provenance belongs to each legacy record, not to runtime state.
    // Never export the migration journal itself.
    final links = await LegacyMemoryMigrationService(
      characterId: id,
    ).existingSourceLinks(payload.events, payload.users);
    for (final row in payload.legacy) {
      final source = LegacyMemoryMigrationService.parseEntry(row)?.id;
      if (links[source] != null) row['memory2Reference'] = links[source];
    }
    return parse(payload.toJson());
  }

  static PeiMemoryPayload parse(dynamic raw) {
    if (raw is! Map) throw const FormatException('Invalid memory package');
    List<Map<String, dynamic>> list(String key) {
      final value = raw[key];
      if (value is! List || value.any((e) => e is! Map)) {
        throw const FormatException('Invalid memory list');
      }
      return value.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }

    void text(Map m, String key, {bool nonempty = false}) {
      if (m[key] is! String ||
          (nonempty && (m[key] as String).trim().isEmpty)) {
        throw const FormatException('Invalid memory text');
      }
    }

    void date(Map m, String key, {bool nullable = false}) {
      if (nullable && m[key] == null) return;
      if (m[key] is! String || DateTime.tryParse(m[key]) == null) {
        throw const FormatException('Invalid memory date');
      }
    }

    void boolean(Map m, String key) {
      if (m[key] is! bool) throw const FormatException('Invalid memory flag');
    }

    void strings(Map m, String key) {
      if (m[key] is! List || (m[key] as List).any((e) => e is! String)) {
        throw const FormatException('Invalid memory references');
      }
    }

    final legacy = list('legacy');
    for (final m in legacy) {
      text(m, 'content');
      for (final key in ['id', 'category', 'sourceMessageId', 'createdAt']) {
        if (m[key] != null && m[key] is! String) {
          throw const FormatException('Invalid legacy field');
        }
      }
      for (final key in ['isPinned', 'isArchived']) {
        if (m[key] != null && m[key] is! bool) {
          throw const FormatException('Invalid legacy flag');
        }
      }
      m.removeWhere(
        (key, value) => !const {
          'id',
          'content',
          'category',
          'createdAt',
          'isPinned',
          'isArchived',
          'sourceMessageId',
          'memory2Reference',
        }.contains(key),
      );
    }
    final events = list('events'), users = list('users');
    for (final group in [events, users]) {
      final ids = <String>{};
      for (final m in group) {
        text(m, 'id', nonempty: true);
        if (!ids.add(m['id'])) {
          throw const FormatException('Duplicate memory ID');
        }
        date(m, 'createdAt');
        date(m, 'updatedAt');
        boolean(m, 'isPinned');
        strings(m, 'sourceMessageIds');
        if (!MemorySourceType.values.any((e) => e.name == m['sourceType'])) {
          throw const FormatException('Invalid memory source');
        }
        if (m['legacySourceId'] != null && m['legacySourceId'] is! String) {
          throw const FormatException('Invalid legacy source');
        }
      }
    }
    for (final m in events) {
      text(m, 'content', nonempty: true);
      date(m, 'occurredAt', nullable: true);
      date(m, 'lastRecalledAt', nullable: true);
      if (m['recallCount'] is! int ||
          m['recallCount'] < 0 ||
          !EventMemoryStatus.values.any((e) => e.name == m['status'])) {
        throw const FormatException('Invalid event state');
      }
      if ((m['metadata'] != null && m['metadata'] is! Map) ||
          (m['metadata'] is Map && (m['metadata'] as Map).isNotEmpty)) {
        throw const FormatException('Unsupported portable event metadata');
      }
      m['metadata'] = <String, dynamic>{};
    }
    for (final m in users) {
      text(m, 'key');
      text(m, 'value');
      if ('${m['key']}${m['value']}'.trim().isEmpty) {
        throw const FormatException('Empty user memory');
      }
      boolean(m, 'userConfirmed');
      strings(m, 'mergedFromIds');
      if (m['supersededById'] != null && m['supersededById'] is! String) {
        throw const FormatException('Invalid user reference');
      }
      if (!UserMemoryStatus.values.any((e) => e.name == m['status'])) {
        throw const FormatException('Invalid user state');
      }
    }
    for (final row in legacy) {
      final link = row['memory2Reference'];
      if (link == null) continue;
      if (link is! Map ||
          link['id'] is! String ||
          !(link['kind'] == 'event' &&
                  events.any((e) => e['id'] == link['id']) ||
              link['kind'] == 'user' &&
                  users.any((e) => e['id'] == link['id']))) {
        throw const FormatException('Invalid portable legacy reference');
      }
      row['memory2Reference'] = {'kind': link['kind'], 'id': link['id']};
    }
    final summary = raw['summary'];
    if (summary is! Map) throw const FormatException('Invalid summary');
    text(summary, 'generatedText');
    text(summary, 'userEditedText');
    date(summary, 'generatedAt', nullable: true);
    date(summary, 'editedAt', nullable: true);
    if (summary['sourceRevision'] is! int || summary['sourceRevision'] < 0) {
      throw const FormatException('Invalid summary revision');
    }
    return PeiMemoryPayload._(
      legacy,
      events.map(EventMemory.fromJson).toList(),
      users.map(UserMemory.fromJson).toList(),
      MemorySummary.fromJson(summary),
    );
  }

  Map<String, dynamic> toJson() => {
    'legacy': legacy,
    'events': events.map((e) => e.toJson()).toList(),
    'users': users.map((e) => e.toJson()).toList(),
    'summary': summary.toJson(),
  };
}
