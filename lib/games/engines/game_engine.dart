import '../models/game_models.dart';

abstract interface class GameEngine<S extends GameStateSnapshot> {
  Future<GameResult<GameSession>> initializeSession(GameSession session);
  Future<GameResult<List<GameEvent>>> startGame(GameSession session);
  Future<GameResult<List<GameEvent>>> handleUserAction(
    GameSession session,
    GameAction action,
  );
  Future<GameResult<List<GameEvent>>> handleCharacterAction(
    GameSession session,
    GameAction action,
  );
  Future<GameResult<List<GameEvent>>> advance(GameSession session);
  Future<GameResult<List<GameEvent>>> pause(GameSession session);
  Future<GameResult<List<GameEvent>>> resume(GameSession session);
  Future<GameResult<List<GameEvent>>> finish(GameSession session);
  Future<GameResult<GameSession>> restore(GameSession session);
}

class UnavailableGameEngine implements GameEngine<BaseGameState> {
  const UnavailableGameEngine();
  static const message = '游戏规则还在准备中，房间框架已经搭好啦。';
  GameResult<T> _unavailable<T>() =>
      const GameResult(GameResultCode.engineUnavailable, message: message);
  @override
  Future<GameResult<GameSession>> initializeSession(
    GameSession session,
  ) async => GameResult.success(session);
  @override
  Future<GameResult<GameSession>> restore(GameSession session) async =>
      GameResult.success(session);
  @override
  Future<GameResult<List<GameEvent>>> startGame(GameSession session) async =>
      _unavailable();
  @override
  Future<GameResult<List<GameEvent>>> handleUserAction(
    GameSession session,
    GameAction action,
  ) async => _unavailable();
  @override
  Future<GameResult<List<GameEvent>>> handleCharacterAction(
    GameSession session,
    GameAction action,
  ) async => _unavailable();
  @override
  Future<GameResult<List<GameEvent>>> advance(GameSession session) async =>
      _unavailable();
  @override
  Future<GameResult<List<GameEvent>>> pause(GameSession session) async =>
      _unavailable();
  @override
  Future<GameResult<List<GameEvent>>> resume(GameSession session) async =>
      _unavailable();
  @override
  Future<GameResult<List<GameEvent>>> finish(GameSession session) async =>
      _unavailable();
}
