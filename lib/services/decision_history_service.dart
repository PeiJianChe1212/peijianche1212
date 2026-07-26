import 'dart:convert';
import 'dart:io';

import '../models/life_decision.dart';
import '../models/life_moment.dart';
import 'character_scope_service.dart';

class DecisionHistoryService {
  DecisionHistoryService({required this.characterId});

  final String characterId;

  static const int _maxItems = 120;
  static const Duration _retention = Duration(days: 30);
  static const Duration _missingEventGrace = Duration(hours: 2);

  Future<File> _file() {
    return CharacterScopeService(characterId).dataFile(
      'life_decision_history.json',
    );
  }

  Future<List<LifeDecision>> loadRecent({
    DateTime? now,
    int limit = 20,
  }) async {
    final time = now ?? DateTime.now();
    final file = await _file();
    if (!await file.exists()) return const [];

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      final items = decoded
          .whereType<Map>()
          .map(LifeDecision.fromJson)
          .where((item) => time.difference(item.decidedAt) <= _retention)
          .toList()
        ..sort((a, b) => b.decidedAt.compareTo(a.decidedAt));
      return items.take(limit).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<LifeDecision>> loadOpen({
    DateTime? now,
    int limit = 40,
  }) async {
    final items = await loadRecent(now: now, limit: _maxItems);
    final open = items.where((item) => item.isOpen).toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return open.take(limit).toList();
  }

  Future<void> addAll(
    Iterable<LifeDecision> incoming, {
    DateTime? now,
  }) async {
    final additions = incoming.toList();
    if (additions.isEmpty) return;

    final time = now ?? DateTime.now();
    final existing = await loadRecent(now: time, limit: _maxItems);
    final merged = <String, LifeDecision>{
      for (final item in existing) item.id: item,
      for (final item in additions) item.id: item,
    };
    await _save(merged.values, now: time);
  }

  /// Life Engine 已经把决定落实为具体生活事件，但时间可能尚未到达。
  Future<void> markMaterialized(
    Iterable<String> decisionIds, {
    DateTime? now,
  }) {
    return _transitionMany(
      decisionIds,
      status: LifeDecisionStatus.materialized,
      reason: 'Life Engine 已生成对应生活事件，等待真实发生时间。',
      now: now,
    );
  }

  Future<void> markCompleted(
    Iterable<String> decisionIds, {
    DateTime? now,
    String reason = '对应生活事件已经到达发生时间。',
  }) {
    return _transitionMany(
      decisionIds,
      status: LifeDecisionStatus.completed,
      reason: reason,
      now: now,
      setCompletedAt: true,
    );
  }

  Future<void> markInterrupted(
    Iterable<String> decisionIds, {
    DateTime? now,
    String reason = '原定时间已过，但没有找到对应的生活事件。',
  }) {
    return _transitionMany(
      decisionIds,
      status: LifeDecisionStatus.interrupted,
      reason: reason,
      now: now,
    );
  }

  Future<void> markCancelled(
    String decisionId, {
    DateTime? now,
    String reason = '决定已取消。',
  }) {
    return _transitionMany(
      [decisionId],
      status: LifeDecisionStatus.cancelled,
      reason: reason,
      now: now,
    );
  }

  Future<void> markPostponed(
    String decisionId, {
    required DateTime newScheduledAt,
    DateTime? now,
    String reason = '决定被延期，等待后续重新安排。',
  }) async {
    final time = now ?? DateTime.now();
    final items = await loadRecent(now: time, limit: _maxItems);
    final updated = items.map((item) {
      if (item.id != decisionId || item.isTerminal) return item;
      return item.copyWith(
        status: LifeDecisionStatus.postponed,
        scheduledAt: newScheduledAt,
        updatedAt: time,
        statusReason: reason,
      );
    });
    await _save(updated, now: time);
  }

  /// 使用事件池的真实情况推进决定状态。
  ///
  /// 有对应事件且已经到点：完成。
  /// 有对应事件但尚未到点：已落实待发生。
  /// 超过原定时间两小时仍无对应事件：被打断。
  Future<DecisionReconcileReport> reconcileWithLifeEvents({
    required Iterable<LifeMomentCandidate> lifeEvents,
    DateTime? now,
  }) async {
    final time = now ?? DateTime.now();
    final eventsByDecisionId = <String, LifeMomentCandidate>{};
    for (final event in lifeEvents) {
      if (event.decisionId.isEmpty) continue;
      eventsByDecisionId[event.decisionId] = event;
    }

    final items = await loadRecent(now: time, limit: _maxItems);
    var materialized = 0;
    var completed = 0;
    var interrupted = 0;

    final updated = items.map((item) {
      if (item.isTerminal) return item;
      final event = eventsByDecisionId[item.id];
      if (event != null) {
        if (!event.occurredAt.isAfter(time)) {
          if (item.status != LifeDecisionStatus.completed) completed++;
          return item.copyWith(
            status: LifeDecisionStatus.completed,
            updatedAt: time,
            completedAt: event.occurredAt,
            statusReason: '对应生活事件已到达发生时间。',
          );
        }
        if (item.status != LifeDecisionStatus.materialized) materialized++;
        return item.copyWith(
          status: LifeDecisionStatus.materialized,
          updatedAt: time,
          statusReason: '对应生活事件已经生成，等待发生时间。',
        );
      }

      final overdueAt = item.scheduledAt.add(_missingEventGrace);
      if (time.isAfter(overdueAt)) {
        interrupted++;
        return item.copyWith(
          status: LifeDecisionStatus.interrupted,
          updatedAt: time,
          statusReason: '原定时间已过两小时，但没有找到对应生活事件。',
        );
      }
      return item;
    }).toList();

    await _save(updated, now: time);
    return DecisionReconcileReport(
      materialized: materialized,
      completed: completed,
      interrupted: interrupted,
    );
  }

  Future<void> _transitionMany(
    Iterable<String> decisionIds, {
    required LifeDecisionStatus status,
    required String reason,
    DateTime? now,
    bool setCompletedAt = false,
  }) async {
    final ids = decisionIds.where((item) => item.isNotEmpty).toSet();
    if (ids.isEmpty) return;
    final time = now ?? DateTime.now();
    final items = await loadRecent(now: time, limit: _maxItems);
    final updated = items.map((item) {
      if (!ids.contains(item.id) || item.isTerminal) return item;
      return item.copyWith(
        status: status,
        updatedAt: time,
        completedAt: setCompletedAt ? time : null,
        statusReason: reason,
      );
    });
    await _save(updated, now: time);
  }

  Future<void> _save(
    Iterable<LifeDecision> incoming, {
    required DateTime now,
  }) async {
    final items = incoming
        .where((item) => now.difference(item.decidedAt) <= _retention)
        .toList()
      ..sort((a, b) => b.decidedAt.compareTo(a.decidedAt));
    final file = await _file();
    await file.writeAsString(
      jsonEncode(items.take(_maxItems).map((item) => item.toJson()).toList()),
      flush: true,
    );
  }

  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }
}

class DecisionReconcileReport {
  const DecisionReconcileReport({
    required this.materialized,
    required this.completed,
    required this.interrupted,
  });

  final int materialized;
  final int completed;
  final int interrupted;
}
