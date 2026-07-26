import 'dart:convert';
import 'dart:io';

import '../models/life_moment.dart';
import 'character_scope_service.dart';

class LifeEventPoolEntry {
  const LifeEventPoolEntry({
    required this.event,
    required this.createdAt,
    this.usedAt,
  });

  /// 已经由 Decision Engine 决定，并由 Life Engine 落实的生活事件。
  final LifeMomentCandidate event;
  final DateTime createdAt;
  final DateTime? usedAt;

  bool get isUsed => usedAt != null;

  /// 兼容旧代码中的 candidate 命名。
  LifeMomentCandidate get candidate => event;

  Map<String, dynamic> toJson() => {
        'event': event.toJson(),
        'createdAt': createdAt.toIso8601String(),
        'usedAt': usedAt?.toIso8601String(),
      };

  factory LifeEventPoolEntry.fromJson(Map<dynamic, dynamic> json) {
    // 兼容 1.3.1 旧数据：旧字段名为 candidate。
    final rawEvent = json['event'] ?? json['candidate'];
    if (rawEvent is! Map) {
      throw const FormatException('生活事件池条目缺少 event。');
    }
    return LifeEventPoolEntry(
      event: LifeMomentCandidate.fromJson(rawEvent),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      usedAt: DateTime.tryParse(json['usedAt']?.toString() ?? ''),
    );
  }
}

class LifeEventPoolService {
  LifeEventPoolService({required this.characterId});

  final String characterId;

  static const Duration _retention = Duration(hours: 36);
  static const Duration _refillInterval = Duration(hours: 8);
  static const int _maxEntries = 40;

  Future<File> _file() {
    return CharacterScopeService(characterId).dataFile(
      'life_event_pool.json',
    );
  }

  Future<List<LifeEventPoolEntry>> loadEntries({DateTime? now}) async {
    final time = now ?? DateTime.now();
    final file = await _file();
    if (!await file.exists()) return const [];

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      final entries = decoded
          .whereType<Map>()
          .map(LifeEventPoolEntry.fromJson)
          .where((entry) => time.difference(entry.createdAt) <= _retention)
          .toList();
      entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return entries;
    } catch (_) {
      return const [];
    }
  }

  /// 只返回已经到达发生时间、并且尚未被 Echo 使用的生活事件。
  ///
  /// 未来事件可以提前存在池中等待，但不能被 Moment Engine 提前读取。
  Future<List<LifeMomentCandidate>> loadAvailable({
    DateTime? now,
    int limit = 8,
  }) async {
    final time = now ?? DateTime.now();
    final entries = await loadEntries(now: time);
    return entries
        .where((entry) => !entry.isUsed)
        .where((entry) => !entry.event.occurredAt.isAfter(time))
        .map((entry) => entry.event)
        .take(limit)
        .toList();
  }

  /// 返回已经决定并生成、但尚未到达发生时间的生活事件。
  Future<List<LifeMomentCandidate>> loadPending({
    DateTime? now,
    int limit = 8,
  }) async {
    final time = now ?? DateTime.now();
    final entries = await loadEntries(now: time);
    final pending = entries
        .where((entry) => !entry.isUsed)
        .where((entry) => entry.event.occurredAt.isAfter(time))
        .map((entry) => entry.event)
        .toList()
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    return pending.take(limit).toList();
  }

  Future<DateTime?> nextPendingAt({DateTime? now}) async {
    final pending = await loadPending(now: now, limit: 1);
    return pending.isEmpty ? null : pending.first.occurredAt;
  }

  Future<bool> shouldRefill({
    DateTime? now,
    int minimumAvailable = 3,
  }) async {
    final time = now ?? DateTime.now();
    final entries = await loadEntries(now: time);
    final unused = entries.where((entry) => !entry.isUsed).toList();
    if (entries.isEmpty) return true;

    // 尚未发生的事件也属于已经安排好的生活，不能因为暂时不可用于 Echo
    // 就反复调用 Decision Engine 重新规划。
    if (unused.length < minimumAvailable) return true;

    final newest = entries.first.createdAt;
    return time.difference(newest) >= _refillInterval;
  }

  /// 只允许写入已经落实完成的生活事件。
  Future<void> addEvents(
    List<LifeMomentCandidate> events, {
    DateTime? now,
  }) async {
    if (events.isEmpty) return;
    final time = now ?? DateTime.now();
    final entries = await loadEntries(now: time);
    final merged = List<LifeEventPoolEntry>.from(entries);

    for (final event in events) {
      if (event.event.trim().isEmpty) continue;
      final duplicate = merged.any(
        (entry) => entry.event.id == event.id ||
            (event.decisionId.isNotEmpty &&
                entry.event.decisionId == event.decisionId) ||
            _fingerprint(entry.event) == _fingerprint(event),
      );
      if (duplicate) continue;
      merged.insert(
        0,
        LifeEventPoolEntry(event: event, createdAt: time),
      );
    }

    await _save(merged.take(_maxEntries).toList());
  }

  /// 兼容旧调用。新代码请使用 addEvents。
  Future<void> addCandidates(
    List<LifeMomentCandidate> candidates, {
    DateTime? now,
  }) {
    return addEvents(candidates, now: now);
  }

  Future<void> markUsed(String eventId, {DateTime? now}) async {
    final time = now ?? DateTime.now();
    final entries = await loadEntries(now: time);
    final updated = entries.map((entry) {
      if (entry.event.id != eventId) return entry;
      return LifeEventPoolEntry(
        event: entry.event,
        createdAt: entry.createdAt,
        usedAt: time,
      );
    }).toList();
    await _save(updated);
  }

  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }

  Future<void> _save(List<LifeEventPoolEntry> entries) async {
    final file = await _file();
    await file.writeAsString(
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
      flush: true,
    );
  }

  String _fingerprint(LifeMomentCandidate event) {
    return '${event.scene}|${event.event}|${event.detail}'
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[，。！？、,.!?：:；;\-—_]'), '');
  }
}
