import 'dart:convert';
import 'dart:io';

import '../config/peilink_runtime.dart';

import '../models/world_event.dart';

class WorldTimelineService {
  static const String _fileName = 'world_timeline.json';
  static const int _maxEvents = 500;
  static const Duration _endedRetention = Duration(days: 30);
  static const Duration _defaultDecisionHorizon = Duration(hours: 24);

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<List<WorldEvent>> loadAll({DateTime? now}) async {
    final time = now ?? DateTime.now();
    final file = await _file();
    if (!await file.exists()) return const [];

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];

      final events = decoded
          .whereType<Map>()
          .map(WorldEvent.fromJson)
          .map((event) => _normalizeStatus(event, time))
          .where((event) => !_isExpired(event, time))
          .toList();
      events.sort(_compareEvents);
      return events;
    } catch (_) {
      return const [];
    }
  }

  Future<List<WorldEvent>> loadActive({
    DateTime? now,
    String? characterId,
    Set<WorldEventType>? types,
    int limit = 80,
    double minimumConfidence = 0.35,
  }) async {
    final time = now ?? DateTime.now();
    final events = await loadAll(now: time);

    return events
        .where((event) {
          if (!event.isActiveAt(time)) return false;
          if (event.normalizedConfidence < minimumConfidence) return false;
          return _matchesFilters(event, characterId: characterId, types: types);
        })
        .take(limit)
        .toList();
  }

  Future<List<WorldEvent>> loadDecisionWindow({
    DateTime? now,
    String? characterId,
    Set<WorldEventType>? types,
    Duration horizon = _defaultDecisionHorizon,
    int limit = 80,
    double minimumConfidence = 0.35,
  }) async {
    final time = now ?? DateTime.now();
    final until = time.add(horizon);
    final events = await loadAll(now: time);

    final relevant = events.where((event) {
      final active = event.isActiveAt(time);
      final scheduled = event.isScheduledWithin(time, until);
      if (!active && !scheduled) return false;
      if (event.normalizedConfidence < minimumConfidence) return false;
      return _matchesFilters(event, characterId: characterId, types: types);
    }).toList();

    relevant.sort((a, b) {
      final aStatus = a.statusAt(time);
      final bStatus = b.statusAt(time);
      final statusOrder = _decisionStatusOrder(
        aStatus,
      ).compareTo(_decisionStatusOrder(bStatus));
      if (statusOrder != 0) return statusOrder;
      final evidenceOrder = _evidenceOrder(
        a.evidence,
      ).compareTo(_evidenceOrder(b.evidence));
      if (evidenceOrder != 0) return evidenceOrder;
      final confidenceOrder = b.normalizedConfidence.compareTo(
        a.normalizedConfidence,
      );
      if (confidenceOrder != 0) return confidenceOrder;
      return a.startAt.compareTo(b.startAt);
    });
    return relevant.take(limit).toList();
  }

  Future<void> upsert(WorldEvent event, {DateTime? now}) async {
    final time = now ?? DateTime.now();
    final events = await loadAll(now: time);
    final updated = List<WorldEvent>.from(events)
      ..removeWhere((item) => item.id == event.id)
      ..add(_normalizeStatus(event, time));
    await _save(updated, now: time);
  }

  Future<void> upsertAll(Iterable<WorldEvent> incoming, {DateTime? now}) async {
    final additions = incoming.toList();
    if (additions.isEmpty) return;

    final time = now ?? DateTime.now();
    final events = await loadAll(now: time);
    final ids = additions.map((event) => event.id).toSet();
    final updated = events.where((event) => !ids.contains(event.id)).toList()
      ..addAll(additions.map((event) => _normalizeStatus(event, time)));
    await _save(updated, now: time);
  }

  Future<void> upsertState(
    WorldEvent event, {
    required String stateKey,
    DateTime? now,
  }) async {
    final key = stateKey.trim();
    if (key.isEmpty) {
      await upsert(event, now: now);
      return;
    }

    final time = now ?? DateTime.now();
    final events = await loadAll(now: time);
    final replacement = event.copyWith(
      metadata: {...event.metadata, 'stateKey': key},
    );

    final updated = <WorldEvent>[];
    for (final current in events) {
      if (current.id == replacement.id) continue;
      if (current.stateKey != key) {
        updated.add(current);
        continue;
      }

      final currentStatus = current.statusAt(time);
      if (currentStatus == WorldEventStatus.active) {
        updated.add(
          current.copyWith(endAt: time, status: WorldEventStatus.ended),
        );
      } else if (currentStatus == WorldEventStatus.ended) {
        updated.add(current);
      }
    }
    updated.add(_normalizeStatus(replacement, time));
    await _save(updated, now: time);
  }

  Future<void> upsertStates(
    Iterable<WorldEvent> incoming, {
    DateTime? now,
  }) async {
    final events = incoming.toList();
    if (events.isEmpty) return;

    for (final event in events) {
      final key = event.stateKey;
      if (key == null) {
        await upsert(event, now: now);
      } else {
        await upsertState(event, stateKey: key, now: now);
      }
    }
  }

  Future<void> remove(String eventId) async {
    final id = eventId.trim();
    if (id.isEmpty) return;

    final events = await loadAll();
    final updated = events.where((event) => event.id != id).toList();
    if (updated.length == events.length) return;
    await _save(updated);
  }

  Future<void> setStatus(
    String eventId,
    WorldEventStatus status, {
    DateTime? now,
  }) async {
    final id = eventId.trim();
    if (id.isEmpty) return;

    final time = now ?? DateTime.now();
    final events = await loadAll(now: time);
    var changed = false;
    final updated = events.map((event) {
      if (event.id != id) return event;
      changed = true;
      return event.copyWith(status: status);
    }).toList();
    if (!changed) return;
    await _save(updated, now: time);
  }

  Future<void> endEvent(String eventId, {DateTime? now}) async {
    final id = eventId.trim();
    if (id.isEmpty) return;

    final time = now ?? DateTime.now();
    final events = await loadAll(now: time);
    var changed = false;
    final updated = events.map((event) {
      if (event.id != id) return event;
      if (event.statusAt(time) == WorldEventStatus.ended) return event;
      changed = true;
      return event.copyWith(endAt: time, status: WorldEventStatus.ended);
    }).toList();
    if (!changed) return;
    await _save(updated, now: time);
  }

  Future<int> endActiveState(
    String stateKey, {
    DateTime? now,
    String? exceptEventId,
  }) async {
    final key = stateKey.trim();
    if (key.isEmpty) return 0;

    final time = now ?? DateTime.now();
    final events = await loadAll(now: time);
    var changed = 0;
    final updated = events.map((event) {
      if (event.stateKey != key ||
          event.id == exceptEventId ||
          !event.isActiveAt(time)) {
        return event;
      }
      changed++;
      return event.copyWith(endAt: time, status: WorldEventStatus.ended);
    }).toList();
    if (changed == 0) return 0;
    await _save(updated, now: time);
    return changed;
  }

  Future<WorldEvent> ensureCurrentTimeState({DateTime? now}) async {
    final time = now ?? DateTime.now();
    final dayStart = DateTime(time.year, time.month, time.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final period = _dayPeriod(time.hour);
    final id = 'time_${_dateKey(time)}_$period';

    final event = WorldEvent(
      id: id,
      type: WorldEventType.time,
      title: _dayPeriodTitle(period),
      description: _timeDescription(time, period),
      startAt: _periodStart(dayStart, period),
      endAt: _periodEnd(dayStart, dayEnd, period),
      createdAt: time,
      source: 'device_clock',
      evidence: WorldEventEvidence.confirmed,
      confidence: 1.0,
      tags: ['time', period, _weekdayName(time.weekday)],
      metadata: {
        'stateKey': 'world.time.current_period',
        'year': time.year,
        'month': time.month,
        'day': time.day,
        'hour': time.hour,
        'weekday': time.weekday,
        'dayPeriod': period,
      },
    );

    await upsertState(event, stateKey: 'world.time.current_period', now: time);
    return event;
  }

  Future<String> buildDecisionContext({
    required String characterId,
    DateTime? now,
    int limit = 30,
  }) async {
    final time = now ?? DateTime.now();
    await ensureCurrentTimeState(now: time);
    final events = await loadDecisionWindow(
      now: time,
      characterId: characterId,
      limit: limit,
    );

    if (events.isEmpty) {
      return '当前世界时间：${_formatTime(time)}。除此之外，暂无已确认的世界状态。';
    }

    final lines = events
        .map((event) => _formatForDecision(event, time))
        .join('\n');
    return '''
【当前世界时间】
${_formatTime(time)}

【当前及未来 24 小时内已确认的世界状态】
$lines

以上内容是角色正在生活其中的真实环境，不是待选剧情。
“未来”状态只能影响对应时间之后的决定，不能当成现在已经发生。
只能基于已经存在的世界状态判断可能发生什么，不要自行创造未记录的天气、节日、店铺、NPC、新闻或公共事件。
''';
  }

  Future<void> compact({DateTime? now}) async {
    final time = now ?? DateTime.now();
    final events = await loadAll(now: time);
    await _save(events, now: time);
  }

  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }

  Future<void> _save(List<WorldEvent> events, {DateTime? now}) async {
    final time = now ?? DateTime.now();
    final normalized = events
        .where((event) => event.id.trim().isNotEmpty)
        .map((event) => _normalizeStatus(event, time))
        .where((event) => !_isExpired(event, time))
        .toList();
    normalized.sort(_compareEvents);

    final unique = <String, WorldEvent>{};
    for (final event in normalized) {
      unique[event.id] = event;
    }

    final kept = unique.values.toList()
      ..sort((a, b) => b.startAt.compareTo(a.startAt));
    final file = await _file();
    await file.writeAsString(
      jsonEncode(kept.take(_maxEvents).map((event) => event.toJson()).toList()),
      flush: true,
    );
  }

  WorldEvent _normalizeStatus(WorldEvent event, DateTime now) {
    final status = event.statusAt(now);
    if (status == event.status) return event;
    return event.copyWith(status: status);
  }

  bool _matchesFilters(
    WorldEvent event, {
    String? characterId,
    Set<WorldEventType>? types,
  }) {
    if (characterId != null &&
        characterId.trim().isNotEmpty &&
        !event.appliesToCharacter(characterId)) {
      return false;
    }
    if (types != null && types.isNotEmpty && !types.contains(event.type)) {
      return false;
    }
    return true;
  }

  bool _isExpired(WorldEvent event, DateTime now) {
    if (event.status == WorldEventStatus.cancelled) return true;
    final end = event.endAt;
    if (end == null) return false;
    return now.difference(end) > _endedRetention;
  }

  int _compareEvents(WorldEvent a, WorldEvent b) {
    final typeOrder = a.type.index.compareTo(b.type.index);
    if (typeOrder != 0) return typeOrder;
    return b.startAt.compareTo(a.startAt);
  }

  int _decisionStatusOrder(WorldEventStatus status) {
    return switch (status) {
      WorldEventStatus.active => 0,
      WorldEventStatus.scheduled => 1,
      WorldEventStatus.ended => 2,
      WorldEventStatus.cancelled => 3,
    };
  }

  String _formatForDecision(WorldEvent event, DateTime now) {
    final timing = event.isActiveAt(now)
        ? '当前有效'
        : '未来：${_formatTime(event.startAt)}开始';
    final location = event.locationName?.trim();
    final locationText = location == null || location.isEmpty
        ? ''
        : '；地点：$location';
    final description = event.description.trim().isEmpty
        ? ''
        : '；${event.description.trim()}';
    final evidence = _evidenceLabel(event.evidence);
    final confidence = (event.normalizedConfidence * 100).round();
    return '- ID=${event.id}；[$timing][${_typeLabel(event.type)}]'
        '[依据：$evidence，可信度：$confidence%] '
        '${event.title}$locationText$description';
  }

  String _typeLabel(WorldEventType type) {
    return switch (type) {
      WorldEventType.time => '时间',
      WorldEventType.weather => '天气',
      WorldEventType.location => '地点',
      WorldEventType.shop => '店铺',
      WorldEventType.npc => 'NPC',
      WorldEventType.festival => '节日',
      WorldEventType.news => '新闻',
      WorldEventType.publicEvent => '公共事件',
      WorldEventType.encounter => '偶遇',
      WorldEventType.mapState => '地图状态',
      WorldEventType.other => '其他',
    };
  }

  int _evidenceOrder(WorldEventEvidence evidence) {
    return switch (evidence) {
      WorldEventEvidence.confirmed => 0,
      WorldEventEvidence.forecast => 1,
      WorldEventEvidence.reported => 2,
      WorldEventEvidence.inferred => 3,
    };
  }

  String _evidenceLabel(WorldEventEvidence evidence) {
    return switch (evidence) {
      WorldEventEvidence.confirmed => '已确认',
      WorldEventEvidence.forecast => '预测',
      WorldEventEvidence.reported => '转述',
      WorldEventEvidence.inferred => '推断',
    };
  }

  String _formatTime(DateTime time) {
    final minute = time.minute.toString().padLeft(2, '0');
    return '${time.year}年${time.month}月${time.day}日 '
        '${_weekdayName(time.weekday)} ${time.hour}:$minute';
  }

  String _dateKey(DateTime time) {
    final month = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    return '${time.year}$month$day';
  }

  String _dayPeriod(int hour) {
    if (hour < 6) return 'late_night';
    if (hour < 9) return 'morning';
    if (hour < 12) return 'forenoon';
    if (hour < 14) return 'noon';
    if (hour < 18) return 'afternoon';
    if (hour < 22) return 'evening';
    return 'night';
  }

  String _dayPeriodTitle(String period) {
    return switch (period) {
      'late_night' => '深夜',
      'morning' => '清晨',
      'forenoon' => '上午',
      'noon' => '中午',
      'afternoon' => '下午',
      'evening' => '傍晚与夜晚',
      _ => '夜深了',
    };
  }

  String _timeDescription(DateTime time, String period) {
    return '现在是${_weekdayName(time.weekday)}的${_dayPeriodTitle(period)}。';
  }

  DateTime _periodStart(DateTime dayStart, String period) {
    final hour = switch (period) {
      'late_night' => 0,
      'morning' => 6,
      'forenoon' => 9,
      'noon' => 12,
      'afternoon' => 14,
      'evening' => 18,
      _ => 22,
    };
    return dayStart.add(Duration(hours: hour));
  }

  DateTime _periodEnd(DateTime dayStart, DateTime dayEnd, String period) {
    final hour = switch (period) {
      'late_night' => 6,
      'morning' => 9,
      'forenoon' => 12,
      'noon' => 14,
      'afternoon' => 18,
      'evening' => 22,
      _ => 24,
    };
    return hour == 24 ? dayEnd : dayStart.add(Duration(hours: hour));
  }

  String _weekdayName(int weekday) {
    return switch (weekday) {
      DateTime.monday => '星期一',
      DateTime.tuesday => '星期二',
      DateTime.wednesday => '星期三',
      DateTime.thursday => '星期四',
      DateTime.friday => '星期五',
      DateTime.saturday => '星期六',
      _ => '星期日',
    };
  }
}
