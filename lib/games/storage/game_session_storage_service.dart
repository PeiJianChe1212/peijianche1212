import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../config/peilink_runtime.dart';
import '../../platform/storage/platform_storage.dart';
import '../models/game_models.dart';
import '../registry/mini_game_registry.dart';

class GameSessionStorageService {
  GameSessionStorageService({this.storage});
  static const namespace = 'games/sessions';
  static const _indexKey = '$namespace/index.json';
  final PlatformStorage? storage;

  Future<PlatformStorage> _store() =>
      storage == null ? PeiLinkRuntime.storage() : Future.value(storage);

  Future<List<GameSession>> loadSessions() async {
    MiniGameRegistry.instance;
    final store = await _store();
    if (!await store.exists(_indexKey)) return <GameSession>[];
    try {
      final decoded = jsonDecode(await store.readText(_indexKey));
      if (decoded is! List) return <GameSession>[];
      final sessions = decoded
          .whereType<Map>()
          .map(GameSession.fromJson)
          .toList();
      sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return sessions;
    } catch (error) {
      debugPrint('GameSessionStorage load failed: ${error.runtimeType}');
      if (store is FailFastPlatformStorage) rethrow;
      return <GameSession>[];
    }
  }

  Future<GameResult<GameSession>> save(GameSession session) async {
    try {
      final sessions = await loadSessions();
      final index = sessions.indexWhere(
        (item) => item.sessionId == session.sessionId,
      );
      if (index >= 0) {
        sessions[index] = session;
      } else {
        sessions.add(session);
      }
      final store = await _store();
      await store.replaceTextSafely(
        _indexKey,
        jsonEncode(sessions.map((item) => item.toJson()).toList()),
      );
      return GameResult.success(session);
    } catch (error) {
      debugPrint('GameSessionStorage save failed: $error');
      return const GameResult(
        GameResultCode.storageFailure,
        message: '游戏房间暂时无法保存。',
      );
    }
  }

  Future<GameSession?> load(String sessionId) async => (await loadSessions())
      .where((item) => item.sessionId == sessionId)
      .firstOrNull;

  Future<GameResult<GameSession>> abandon(String sessionId) async {
    final session = await load(sessionId);
    if (session == null) {
      return const GameResult(GameResultCode.invalidState, message: '游戏房间不存在。');
    }
    final abandoned = session.copyWith(status: GameSessionStatus.abandoned);
    return save(abandoned);
  }

  /// Permanently removes a session from the index (not just marking abandoned).
  Future<void> delete(String sessionId) async {
    final sessions = await loadSessions();
    sessions.removeWhere((s) => s.sessionId == sessionId);
    final store = await _store();
    await store.replaceTextSafely(
      _indexKey,
      jsonEncode(sessions.map((item) => item.toJson()).toList()),
    );
  }

  Future<List<GameSession>> loadContinuable() async => (await loadSessions())
      .where(
        (item) => !{
          GameSessionStatus.finished,
          GameSessionStatus.abandoned,
        }.contains(item.status),
      )
      .toList();

  /// 入口短路用：返回某游戏最近一个可继续的 active session。
  /// 第一版只支持单活跃局，取 updatedAt 最新者；没有则返回 null。
  Future<GameSession?> loadActiveSessionForGame(String gameId) async {
    final matches = (await loadContinuable())
        .where((item) => item.gameId == gameId)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return matches.firstOrNull;
  }
}
