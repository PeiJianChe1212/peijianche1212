import 'dart:convert';
import 'dart:io';


import '../models/activity_status.dart';
import '../models/today_event.dart';
import 'character_scope_service.dart';

class TodayService {
  TodayService({this.characterId});

  final String? characterId;

  Future<File> _timelineFile() {
    return CharacterScopeService(characterId).dataFile(
      'today_timeline.json',
      legacyDefaultFileName: 'today_timeline.json',
    );
  }

  String _dayKey(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  Future<List<TodayEvent>> loadToday({DateTime? now}) async {
    final time = now ?? DateTime.now();
    final file = await _timelineFile();
    if (!await file.exists()) return [];

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return [];
      if (decoded['date']?.toString() != _dayKey(time)) {
        await clearToday();
        return [];
      }
      final rawEvents = decoded['events'];
      if (rawEvents is! List) return [];
      final events =
          rawEvents
              .whereType<Map>()
              .map(TodayEvent.fromJson)
              .where((event) => event.title.trim().isNotEmpty)
              .toList()
            ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
      return events;
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveToday(List<TodayEvent> events, DateTime now) async {
    final file = await _timelineFile();
    await file.writeAsString(
      jsonEncode({
        'date': _dayKey(now),
        'events': events.map((event) => event.toJson()).toList(),
      }),
      flush: true,
    );
  }

  Future<bool> recordActivity(ActivityStatus activity, {DateTime? now}) async {
    final time = now ?? DateTime.now();
    final events = await loadToday(now: time);
    final activityEvents = events.where((event) => event.kind == 'activity');
    if (activityEvents.isNotEmpty && activityEvents.last.activityId == activity.id) {
      return false;
    }

    events.add(
      TodayEvent(
        id: '${time.microsecondsSinceEpoch}_${activity.id}',
        activityId: activity.id,
        kind: 'activity',
        title: activity.label,
        emoji: activity.emoji,
        story: activity.detail,
        occurredAt: time,
      ),
    );

    if (events.length > 24) {
      events.removeRange(0, events.length - 24);
    }
    await _saveToday(events, time);
    return true;
  }


  Future<bool> recordLifeTrace({
    required String id,
    required String kind,
    required String title,
    required String emoji,
    required String story,
    DateTime? now,
  }) async {
    final time = now ?? DateTime.now();
    final events = await loadToday(now: time);
    if (events.any((event) => event.id == id)) return false;
    events.add(
      TodayEvent(
        id: id,
        activityId: 'life_$kind',
        kind: kind,
        title: title,
        emoji: emoji,
        story: story,
        occurredAt: time,
      ),
    );
    events.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    if (events.length > 30) events.removeRange(0, events.length - 30);
    await _saveToday(events, time);
    return true;
  }

  Future<void> clearToday() async {
    final file = await _timelineFile();
    if (await file.exists()) await file.delete();
  }
}
