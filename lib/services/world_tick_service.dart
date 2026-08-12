import 'dart:convert';
import 'dart:io';

import '../config/peilink_runtime.dart';

import '../models/world_tick_state.dart';
import 'character_registry_service.dart';
import 'decision_history_service.dart';
import 'life_event_pool_service.dart';
import 'world_simulation_service.dart';
import 'world_timeline_service.dart';

class WorldTickService {
  static const String _fileName = 'world_tick_state.json';
  static const Duration _minimumInterval = Duration(minutes: 5);

  static bool _isAdvancing = false;

  final WorldTimelineService _worldTimeline = WorldTimelineService();
  final CharacterRegistryService _characterRegistry =
      CharacterRegistryService();
  final WorldSimulationService _worldSimulation = WorldSimulationService();

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<WorldTickState> loadState() async {
    final file = await _file();
    if (!await file.exists()) return WorldTickState.initial();

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return WorldTickState.initial();
      return WorldTickState.fromJson(decoded);
    } catch (_) {
      return WorldTickState.initial();
    }
  }

  /// 按真实设备时间推进一次世界。
  ///
  /// 这一层只推进已有世界状态和已有生活安排，不调用聊天模型，
  /// 因此不会因为应用进入前台或定时检查而产生 API 费用。
  Future<WorldTickReport> advance({
    DateTime? now,
    bool force = false,
    bool markForeground = false,
  }) async {
    final time = now ?? DateTime.now();
    final state = await loadState();
    final previous = state.lastTickAt;
    final elapsed = previous == null
        ? Duration.zero
        : time.difference(previous);

    if (_isAdvancing ||
        (!force && previous != null && elapsed < _minimumInterval)) {
      return WorldTickReport(
        executed: false,
        tickAt: time,
        previousTickAt: previous,
        elapsed: elapsed.isNegative ? Duration.zero : elapsed,
        crossedDayBoundary: false,
        crossedTimePeriod: false,
        characterSnapshots: const [],
      );
    }

    _isAdvancing = true;
    try {
      final crossedDay = previous != null && !_isSameDay(previous, time);
      final crossedPeriod =
          previous != null &&
          (_dayPeriod(previous.hour) != _dayPeriod(time.hour) || crossedDay);

      // 当前时间状态是世界里唯一可以直接由设备确认的状态。
      await _worldTimeline.ensureCurrentTimeState(now: time);
      final simulationReport = await _worldSimulation.advance(now: time);
      await _worldTimeline.compact(now: time);

      final characters = await _characterRegistry.loadCharacters();
      final snapshots = <CharacterTickSnapshot>[];

      for (final character in characters) {
        try {
          final pool = LifeEventPoolService(characterId: character.id);
          final entries = await pool.loadEntries(now: time);
          final available = await pool.loadAvailable(now: time, limit: 40);
          final pending = await pool.loadPending(now: time, limit: 40);
          final decisionReport =
              await DecisionHistoryService(
                characterId: character.id,
              ).reconcileWithLifeEvents(
                lifeEvents: entries.map((entry) => entry.event),
                now: time,
              );

          snapshots.add(
            CharacterTickSnapshot(
              characterId: character.id,
              availableLifeEvents: available.length,
              pendingLifeEvents: pending.length,
              nextPendingAt: pending.isEmpty ? null : pending.first.occurredAt,
              decisionsCompleted: decisionReport.completed,
              decisionsInterrupted: decisionReport.interrupted,
            ),
          );
        } catch (_) {
          // 单个角色数据损坏不能阻止整个世界继续走时。
        }
      }

      final nextState = state.copyWith(
        lastTickAt: time,
        lastForegroundAt: markForeground ? time : state.lastForegroundAt,
        sequence: state.sequence + 1,
      );
      await _saveState(nextState);

      return WorldTickReport(
        executed: true,
        tickAt: time,
        previousTickAt: previous,
        elapsed: elapsed.isNegative ? Duration.zero : elapsed,
        crossedDayBoundary: crossedDay,
        crossedTimePeriod: crossedPeriod,
        characterSnapshots: snapshots,
        worldEffectsCreated: simulationReport.effectsCreated,
        worldEffectsRefreshed: simulationReport.effectsRefreshed,
        worldEffectsEnded: simulationReport.effectsEnded,
        worldStatesEnded: simulationReport.statesEnded,
      );
    } finally {
      _isAdvancing = false;
    }
  }

  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }

  Future<void> _saveState(WorldTickState state) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(state.toJson()), flush: true);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
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
}
