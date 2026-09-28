import 'dart:math';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_guess_decision.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_semantic_judge.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/games/hosting/character_host_agent.dart';
import 'package:peijianche_app/games/models/game_models.dart';
import 'package:peijianche_app/games/participation/character_game_action.dart';
import 'package:peijianche_app/games/registry/mini_game_registry.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_engine.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_models.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_puzzle_registry.dart';

void main() {
  MiniGameRegistry.instance;
  final puzzle = TurtleSoupPuzzleRegistry.puzzles.first;

  GameSession base({
    GameHost host = const GameHost.system(),
    GameStateSnapshot? state,
  }) {
    final now = DateTime(2026, 9, 20, 4);
    return GameSession(
      sessionId: 'soup-1',
      gameId: MiniGameRegistry.turtleSoupId,
      createdAt: now,
      updatedAt: now,
      status: GameSessionStatus.ready,
      host: host,
      participants: const [
        GameParticipant(
          participantId: 'user:1',
          type: GameParticipantType.user,
          displayName: '我',
        ),
      ],
      gameState:
          state ?? BaseGameState(participantState: {'puzzleId': puzzle.id}),
    );
  }

  TurtleSoupState ready() => TurtleSoupState(
    puzzleId: puzzle.id,
    title: puzzle.title,
    surface: puzzle.surface,
    truth: puzzle.truth,
    hints: puzzle.hints,
  );

  GameAction action(String kind, [String text = '']) => GameAction(
    type: GameActionType.custom,
    actorParticipantId: 'user:1',
    payload: {'kind': kind, 'text': text},
  );

  GameSession apply(GameSession session, GameResult<List<GameEvent>> result) {
    var state = session.gameState;
    var status = session.status;
    final messages = [...session.messages];
    for (final event in result.value ?? const <GameEvent>[]) {
      if (event.state != null) {
        state = event.state!;
      }
      if (event.message != null) messages.add(event.message!);
      if (event.type == GameEventType.gameFinished) {
        status = GameSessionStatus.finished;
      }
    }
    return session.copyWith(
      gameState: state,
      status: status,
      messages: messages,
    );
  }

  test('local puzzle registry is stable, original and sufficiently hinted', () {
    expect(TurtleSoupPuzzleRegistry.puzzles, hasLength(22));
    expect(
      TurtleSoupPuzzleRegistry.puzzles.where(
        (item) => item.difficulty == TurtleSoupDifficulty.easy,
      ),
      hasLength(8),
    );
    expect(
      TurtleSoupPuzzleRegistry.puzzles.where(
        (item) => item.difficulty == TurtleSoupDifficulty.normal,
      ),
      hasLength(8),
    );
    expect(
      TurtleSoupPuzzleRegistry.puzzles.where(
        (item) => item.difficulty == TurtleSoupDifficulty.hard,
      ),
      hasLength(6),
    );
    expect(
      TurtleSoupPuzzleRegistry.puzzles.map((item) => item.id).toSet(),
      hasLength(TurtleSoupPuzzleRegistry.puzzles.length),
    );
    expect(
      TurtleSoupPuzzleRegistry.puzzles.every((item) => item.title.isNotEmpty),
      isTrue,
    );
    expect(
      TurtleSoupPuzzleRegistry.puzzles.every((item) => item.surface.isNotEmpty),
      isTrue,
    );
    expect(
      TurtleSoupPuzzleRegistry.puzzles.every(
        (item) => item.reasoningDimensions.isNotEmpty,
      ),
      isTrue,
    );
    expect(
      TurtleSoupPuzzleRegistry.puzzles.every(
        (item) => item.yesKeywords.isNotEmpty && item.noKeywords.isNotEmpty,
      ),
      isTrue,
    );
    for (final puzzle in TurtleSoupPuzzleRegistry.puzzles) {
      expect(TurtleSoupPuzzleRegistry.byId(puzzle.id), same(puzzle));
    }
    expect(
      TurtleSoupPuzzleRegistry.puzzles.every((item) => item.truth.isNotEmpty),
      isTrue,
    );
    expect(
      TurtleSoupPuzzleRegistry.puzzles.every((item) => item.hints.length >= 2),
      isTrue,
    );
    expect(
      TurtleSoupPuzzleRegistry.puzzles.every(
        (item) => item.requiredTruthPoints.isNotEmpty,
      ),
      isTrue,
    );
  });

  test('difficulty metadata is complete and multiplayer avoids easy', () {
    expect(
      TurtleSoupPuzzleRegistry.puzzles.map((item) => item.difficulty).toSet(),
      containsAll(TurtleSoupDifficulty.values),
    );
    for (var seed = 0; seed < 30; seed++) {
      final selected = TurtleSoupPuzzleRegistry.randomForParticipants(
        4,
        Random(seed),
      );
      expect(selected.difficulty, isNot(TurtleSoupDifficulty.easy));
      expect(
        selected.requiredTruthPoints.length,
        greaterThanOrEqualTo(
          selected.difficulty == TurtleSoupDifficulty.hard ? 4 : 2,
        ),
      );
      expect(selected.reasoningDimensions.length, greaterThanOrEqualTo(4));
    }
    const legacy = TurtleSoupPuzzle(
      id: 'legacy',
      title: '旧题',
      surface: '旧汤面',
      truth: '旧汤底',
      hints: [],
      requiredTruthPoints: [],
    );
    expect(legacy.difficulty, TurtleSoupDifficulty.easy);
  });

  test('random selection always returns a registered stable puzzle', () {
    final selected = TurtleSoupPuzzleRegistry.random();
    expect(TurtleSoupPuzzleRegistry.puzzles, contains(selected));
    expect(selected.id, isNotEmpty);
    expect(TurtleSoupPuzzleRegistry.byId(selected.id).id, selected.id);
  });

  test(
    'play-again selection excludes the current puzzle when candidates exist',
    () {
      for (final puzzle in TurtleSoupPuzzleRegistry.puzzles) {
        final participantCount = puzzle.difficulty == TurtleSoupDifficulty.easy
            ? 1
            : 4;
        for (var seed = 0; seed < 10; seed++) {
          final selected =
              TurtleSoupPuzzleRegistry.randomForParticipantsExcluding(
                participantCount,
                puzzle.id,
                Random(seed),
              );
          expect(selected.id, isNot(puzzle.id));
          if (participantCount > 1) {
            expect(selected.difficulty, isNot(TurtleSoupDifficulty.easy));
          }
        }
      }
    },
  );

  test('strong state serializes every gameplay field exactly', () {
    final original = ready().copyWith(
      usedHintCount: 1,
      questionCount: 3,
      guessCount: 2,
      phase: TurtleSoupPhase.finished,
      isSolved: true,
      startedAt: DateTime(2026, 9, 20, 4, 1),
      finishedAt: DateTime(2026, 9, 20, 4, 5),
    );
    final restored = TurtleSoupState.fromJson(original.toJson());
    expect(restored.puzzleId, original.puzzleId);
    expect(restored.title, original.title);
    expect(restored.surface, original.surface);
    expect(restored.truth, original.truth);
    expect(restored.hints, original.hints);
    expect(restored.usedHintCount, 1);
    expect(restored.questionCount, 3);
    expect(restored.guessCount, 2);
    expect(restored.phase, TurtleSoupPhase.finished);
    expect(restored.isSolved, isTrue);
    expect(restored.startedAt, original.startedAt);
    expect(restored.finishedAt, original.finishedAt);
  });

  test('session codec restores concrete turtle soup state', () {
    final encoded = base(state: ready()).encode();
    final restored = GameSession.decode(encoded);
    expect(restored.gameState, isA<TurtleSoupState>());
    expect((restored.gameState as TurtleSoupState).puzzleId, puzzle.id);
    expect(restored.messages, isEmpty);
  });

  test(
    'initialize honors selected puzzle and user plus host is valid',
    () async {
      const engine = TurtleSoupEngine();
      final result = await engine.initializeSession(base());
      expect(result.isSuccess, isTrue);
      expect(result.value!.participants, hasLength(1));
      expect(result.value!.host.type, GameHostType.systemHost);
      expect((result.value!.gameState as TurtleSoupState).puzzleId, puzzle.id);
      expect(
        (result.value!.gameState as TurtleSoupState).phase,
        TurtleSoupPhase.ready,
      );
    },
  );

  test(
    'start moves ready to questioning and publishes only the surface',
    () async {
      const engine = TurtleSoupEngine();
      final result = await engine.startGame(base(state: ready()));
      expect(result.isSuccess, isTrue);
      expect(result.value, hasLength(2));
      expect(result.value!.first.type, GameEventType.sessionStarted);
      expect(
        (result.value!.first.state as TurtleSoupState).phase,
        TurtleSoupPhase.questioning,
      );
      expect(result.value!.last.message!.type, GameMessageType.puzzle);
      expect(result.value!.last.message!.content, puzzle.surface);
      expect(
        result.value!.last.message!.content,
        isNot(contains(puzzle.truth)),
      );
    },
  );

  test(
    'characters do not auto-act and legacy bypass remains rejected',
    () async {
      const engine = TurtleSoupEngine();
      final withCharacter = GameSession(
        sessionId: 'passive-character',
        gameId: MiniGameRegistry.turtleSoupId,
        createdAt: DateTime(2026, 9, 20),
        updatedAt: DateTime(2026, 9, 20),
        status: GameSessionStatus.ready,
        host: const GameHost.system(),
        participants: const [
          GameParticipant(
            participantId: 'user:1',
            type: GameParticipantType.user,
            displayName: '我',
          ),
          GameParticipant(
            participantId: 'character:c1',
            type: GameParticipantType.character,
            displayName: '角色',
            characterId: 'c1',
          ),
        ],
        gameState: ready(),
      );
      final started = await engine.startGame(withCharacter);
      expect(started.isSuccess, isTrue);
      expect(
        started.value!.where(
          (event) => event.message?.senderId == 'character:c1',
        ),
        isEmpty,
      );
      final characterAction = await engine.handleCharacterAction(
        withCharacter,
        action('question', '自动提问'),
      );
      expect(characterAction.code, GameResultCode.invalidAction);
    },
  );

  test(
    'legal character action enters the normal engine message path',
    () async {
      final value =
          base(
            state: ready().copyWith(phase: TurtleSoupPhase.questioning),
          ).copyWith(
            status: GameSessionStatus.playing,
            participants: [
              ...base().participants,
              const GameParticipant(
                participantId: 'character:c1',
                type: GameParticipantType.character,
                displayName: '角色',
                characterId: 'c1',
              ),
            ],
          );
      final result = await const TurtleSoupEngine().handleCharacterAction(
        value,
        const CharacterGameAction(
          actorParticipantId: 'character:c1',
          type: CharacterGameActionType.askQuestion,
          content: '这件事发生在室内吗？',
        ).toEngineAction(),
      );
      expect(result.isSuccess, isTrue);
      final messages = result.value!
          .map((event) => event.message)
          .whereType<GameMessage>()
          .toList();
      expect(messages, hasLength(2));
      expect(messages.first.senderId, 'character:c1');
      expect(messages.first.type, GameMessageType.question);
      expect(messages.last.senderId, 'host');
    },
  );

  test(
    'system host classifies yes, no and irrelevant deterministically',
    () async {
      const engine = TurtleSoupEngine();
      final session = base(
        state: ready().copyWith(phase: TurtleSoupPhase.questioning),
      );
      Future<String> answer(String text) async {
        final result = await engine.handleUserAction(
          session,
          action('question', text),
        );
        expect(result.isSuccess, isTrue);
        return result.value!.last.message!.content;
      }

      expect(await answer('她是在帮忙检查闭馆吗？'), '是的。');
      expect(await answer('她是因为偷书被惩罚吗？'), '不是。');
      expect(await answer('这和早餐有关吗？'), '无关。');
      expect(await answer('她喜欢蓝色吗？'), contains('无法确定'));
    },
  );

  test('questions add timeline pair and increment once', () async {
    const engine = TurtleSoupEngine();
    final session = base(
      state: ready().copyWith(phase: TurtleSoupPhase.questioning),
    );
    final result = await engine.handleUserAction(
      session,
      action('question', '她在工作吗？'),
    );
    final next = apply(session, result);
    expect((next.gameState as TurtleSoupState).questionCount, 1);
    expect(next.messages, hasLength(2));
    expect(next.messages.first.type, GameMessageType.question);
    expect(next.messages.last.type, GameMessageType.answer);
    expect(
      next.messages.every(
        (item) => item.visibility == GameMessageVisibility.public,
      ),
      isTrue,
    );
  });

  test('hints are ordered, counted once and then exhausted', () async {
    const engine = TurtleSoupEngine();
    var session = base(
      state: ready().copyWith(phase: TurtleSoupPhase.questioning),
    );
    final first = await engine.handleUserAction(session, action('hint'));
    session = apply(session, first);
    expect(session.messages.last.content, puzzle.hints.first);
    expect((session.gameState as TurtleSoupState).usedHintCount, 1);
    final second = await engine.handleUserAction(session, action('hint'));
    session = apply(session, second);
    expect(session.messages.last.content, puzzle.hints[1]);
    expect((session.gameState as TurtleSoupState).usedHintCount, 2);
    final exhausted = await engine.handleUserAction(session, action('hint'));
    expect(exhausted.code, GameResultCode.invalidAction);
    expect(exhausted.message, contains('用完'));
  });

  test(
    'incorrect guess returns to questioning without revealing truth',
    () async {
      const engine = TurtleSoupEngine();
      final session = base(
        state: ready().copyWith(phase: TurtleSoupPhase.guessing),
      );
      final result = await engine.handleUserAction(
        session,
        action('guess', '她只是忘记时间了'),
      );
      final next = apply(session, result);
      final state = next.gameState as TurtleSoupState;
      expect(state.phase, TurtleSoupPhase.questioning);
      expect(state.guessCount, 1);
      expect(state.isSolved, isFalse);
      expect(next.status, isNot(GameSessionStatus.finished));
      expect(
        next.messages.any((item) => item.type == GameMessageType.reveal),
        isFalse,
      );
    },
  );

  test('complete guess solves, reveals and finishes', () async {
    final engine = TurtleSoupEngine(semanticJudge: _AcceptedGuessJudge());
    final session = base(
      state: ready().copyWith(phase: TurtleSoupPhase.guessing),
    );
    final text = puzzle.requiredTruthPoints.join('，');
    final result = await engine.handleUserAction(
      session,
      action('guess', text),
    );
    final next = apply(session, result);
    final state = next.gameState as TurtleSoupState;
    expect(state.phase, TurtleSoupPhase.finished);
    expect(state.isSolved, isTrue);
    expect(state.solvedByParticipantId, 'user:1');
    expect(state.finishedAt, isNotNull);
    expect(next.status, GameSessionStatus.finished);
    expect(next.messages.last.type, GameMessageType.reveal);
    expect(next.messages.last.content, puzzle.truth);
  });

  test('manual reveal finishes unsolved and exposes truth once', () async {
    const engine = TurtleSoupEngine();
    final session = base(
      state: ready().copyWith(phase: TurtleSoupPhase.questioning),
    );
    final result = await engine.handleUserAction(session, action('reveal'));
    final next = apply(session, result);
    final state = next.gameState as TurtleSoupState;
    expect(state.phase, TurtleSoupPhase.revealed);
    expect(state.isSolved, isFalse);
    expect(state.solvedByParticipantId, isNull);
    expect(next.status, GameSessionStatus.finished);
    expect(
      next.messages.where((item) => item.type == GameMessageType.reveal),
      hasLength(1),
    );
  });

  test(
    'play again keeps roster and host but resets round and puzzle',
    () async {
      const engine = TurtleSoupEngine();
      final ended =
          base(
            host: const GameHost.character('host-1'),
            state: ready().copyWith(
              phase: TurtleSoupPhase.finished,
              isSolved: true,
              solvedByParticipantId: 'user:1',
            ),
          ).copyWith(
            status: GameSessionStatus.finished,
            messages: [
              GameMessage(
                sessionId: 'soup-1',
                senderId: 'host',
                type: GameMessageType.reveal,
                content: puzzle.truth,
              ),
            ],
          );
      final result = await engine.playAgain(ended);
      expect(result.isSuccess, isTrue);
      final replay = result.value!;
      final replayState = replay.gameState as TurtleSoupState;
      expect(replay.host.characterId, 'host-1');
      expect(
        replay.participants.map((item) => item.participantId),
        ended.participants.map((item) => item.participantId),
      );
      expect(replay.status, GameSessionStatus.playing);
      expect(replay.messages, isEmpty);
      expect(replayState.phase, TurtleSoupPhase.questioning);
      expect(replayState.puzzleId, isNot(puzzle.id));
      expect(replayState.questionCount, 0);
      expect(replayState.guessCount, 0);
      expect(replayState.usedHintCount, 0);
      expect(replayState.solvedByParticipantId, isNull);
    },
  );

  test(
    'character host receives authoritative semantic and only styles wording',
    () async {
      final renderer = _FakeHostRenderer('对，就是这个方向。');
      final engine = TurtleSoupEngine(hostRenderer: renderer);
      final session = base(
        host: const GameHost.character('c1'),
        state: ready().copyWith(phase: TurtleSoupPhase.questioning),
      );
      final result = await engine.handleUserAction(
        session,
        action('question', '她在帮忙吗？'),
      );
      expect(renderer.calls, 1);
      expect(renderer.lastRequest!.characterId, 'c1');
      expect(renderer.lastRequest!.view.hiddenTruth, puzzle.truth);
      expect(
        renderer.lastRequest!.view.semanticResult.type,
        GameHostSemanticType.answerYes,
      );
      expect(renderer.lastRequest!.gameUserIdentity.displayName, '我');
      expect(result.value!.last.message!.content, '对，就是这个方向。');
    },
  );

  test(
    'empty, failed and leaking character output uses canonical fallback',
    () async {
      final session = base(
        host: const GameHost.character('c1'),
        state: ready().copyWith(phase: TurtleSoupPhase.questioning),
      );
      final malformed = await TurtleSoupEngine(
        hostRenderer: _FakeHostRenderer(''),
      ).handleUserAction(session, action('question', '问题'));
      expect(malformed.value!.last.message!.content, contains('无法确定'));
      final failed = await TurtleSoupEngine(
        hostRenderer: _FakeHostRenderer('', fail: true),
      ).handleUserAction(session, action('question', '问题'));
      expect(failed.value!.last.message!.content, contains('无法确定'));
      final leaking = await TurtleSoupEngine(
        hostRenderer: _FakeHostRenderer(puzzle.truth),
      ).handleUserAction(session, action('question', '问题'));
      expect(leaking.value!.last.message!.content, contains('无法确定'));
      expect(
        leaking.value!.last.message!.content,
        isNot(contains(puzzle.truth)),
      );
    },
  );

  test('renderer wording cannot change Engine guess authority', () async {
    final renderer = _FakeHostRenderer('答对了！');
    final session = base(
      host: const GameHost.character('c1'),
      state: ready().copyWith(phase: TurtleSoupPhase.questioning),
    );
    final result = await TurtleSoupEngine(
      hostRenderer: renderer,
    ).handleUserAction(session, action('guess', '一个不完整的猜测'));
    final next = apply(session, result);
    expect(
      renderer.lastRequest!.view.semanticResult.type,
      GameHostSemanticType.guessIncorrect,
    );
    expect((next.gameState as TurtleSoupState).isSolved, isFalse);
    expect(next.status, isNot(GameSessionStatus.finished));
    expect(
      next.messages.where((item) => item.type == GameMessageType.reveal),
      isEmpty,
    );
  });

  test(
    'official reveal authorizes truth through character host pipeline',
    () async {
      final renderer = _FakeHostRenderer(puzzle.truth);
      final session = base(
        host: const GameHost.character('c1'),
        state: ready().copyWith(phase: TurtleSoupPhase.questioning),
      );
      final result = await TurtleSoupEngine(
        hostRenderer: renderer,
      ).handleUserAction(session, action('reveal'));
      expect(
        renderer.lastRequest!.view.semanticResult.type,
        GameHostSemanticType.reveal,
      );
      expect(renderer.lastRequest!.view.truthMayBeRevealed, isTrue);
      expect(result.value![1].message!.content, puzzle.truth);
    },
  );

  test('restore rejects base state and preserves a valid state', () async {
    const engine = TurtleSoupEngine();
    expect((await engine.restore(base())).code, GameResultCode.invalidState);
    final valid = base(state: ready());
    final restored = await engine.restore(valid);
    expect(restored.isSuccess, isTrue);
    expect(identical(restored.value, valid), isTrue);
  });
}

class _AcceptedGuessJudge
    implements TurtleSoupSemanticJudge, TurtleSoupGuessJudge {
  @override
  Future<TurtleSoupJudgment?> judge(TurtleSoupJudgeRequest request) async =>
      null;
  @override
  Future<bool> judgeGuess(TurtleSoupGuessRequest request) async => true;
}

class _FakeHostRenderer implements CharacterHostResponseRenderer {
  _FakeHostRenderer(this.response, {this.fail = false});
  final String response;
  final bool fail;
  int calls = 0;
  CharacterHostRenderRequest? lastRequest;
  @override
  Future<String> render(CharacterHostRenderRequest request) async {
    calls++;
    lastRequest = request;
    if (fail) throw StateError('renderer failed');
    return response;
  }
}
