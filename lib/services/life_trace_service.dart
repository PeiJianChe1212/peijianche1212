import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/life_trace.dart';
import 'today_service.dart';

class LifeTraceService {
  LifeTraceService({TodayService? todayService})
      : _todayService = todayService ?? TodayService();

  final TodayService _todayService;

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/life_traces.json');
  }

  String _dayKey(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Future<Map<String, dynamic>> _loadRaw() async {
    final file = await _file();
    if (!await file.exists()) {
      return {'traces': <dynamic>[], 'lastSeenAt': null};
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return {'traces': <dynamic>[], 'lastSeenAt': null};
  }

  Future<void> _saveRaw(Map<String, dynamic> data) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(data), flush: true);
  }

  Future<List<LifeTrace>> loadRecent({int limit = 3}) async {
    final raw = await _loadRaw();
    final items = (raw['traces'] as List? ?? const [])
        .whereType<Map>()
        .map(LifeTrace.fromJson)
        .where((item) => item.title.trim().isNotEmpty)
        .toList();

    final todayEvents = await _todayService.loadToday();
    for (final event in todayEvents) {
      if (items.any((item) => item.id == event.id)) continue;
      items.add(
        LifeTrace(
          id: event.id,
          kind: event.kind,
          title: event.title,
          emoji: event.emoji,
          detail: event.story,
          occurredAt: event.occurredAt,
        ),
      );
    }

    items.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return items.take(limit).toList();
  }

  Future<DateTime?> beginVisit({DateTime? now}) async {
    final time = now ?? DateTime.now();
    final raw = await _loadRaw();
    final previous = DateTime.tryParse(raw['lastSeenAt']?.toString() ?? '');
    raw['lastSeenAt'] = time.toIso8601String();
    await _saveRaw(raw);
    await record(
      kind: 'returned',
      title: '你回来了',
      emoji: '🌙',
      detail: '你走进了他的今天。',
      occurredAt: time,
      dedupeKey: 'returned_${_dayKey(time)}',
      addToToday: true,
    );
    return previous;
  }

  Future<void> recordConversation({DateTime? now}) async {
    final time = now ?? DateTime.now();
    await record(
      kind: 'conversation',
      title: '和你聊了一会儿',
      emoji: '💬',
      detail: '今天的安静，被你们的对话轻轻打破了。',
      occurredAt: time,
      dedupeKey: 'conversation_${_dayKey(time)}',
      addToToday: true,
    );
  }

  Future<void> recordInitiative({DateTime? now}) async {
    final time = now ?? DateTime.now();
    await record(
      kind: 'initiative',
      title: '给你留了消息',
      emoji: '✉️',
      detail: '想起你的时候，他先敲了敲聊天框。',
      occurredAt: time,
      dedupeKey: 'initiative_${_dayKey(time)}',
      addToToday: true,
    );
  }

  Future<bool> record({
    required String kind,
    required String title,
    required String emoji,
    required String detail,
    DateTime? occurredAt,
    String? dedupeKey,
    bool addToToday = false,
  }) async {
    final time = occurredAt ?? DateTime.now();
    final raw = await _loadRaw();
    final traces = (raw['traces'] as List? ?? const [])
        .whereType<Map>()
        .map(LifeTrace.fromJson)
        .toList();
    final id = dedupeKey ?? '${time.microsecondsSinceEpoch}_$kind';
    if (traces.any((item) => item.id == id)) return false;

    traces.add(
      LifeTrace(
        id: id,
        kind: kind,
        title: title,
        emoji: emoji,
        detail: detail,
        occurredAt: time,
      ),
    );
    traces.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    if (traces.length > 40) traces.removeRange(0, traces.length - 40);
    raw['traces'] = traces.map((item) => item.toJson()).toList();
    await _saveRaw(raw);

    if (addToToday) {
      await _todayService.recordLifeTrace(
        id: id,
        kind: kind,
        title: title,
        emoji: emoji,
        story: detail,
        now: time,
      );
    }
    return true;
  }

  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }
}
