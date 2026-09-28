import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/games/hosting/character_host_agent.dart';
import 'package:peijianche_app/games/models/game_models.dart';
import 'package:peijianche_app/games/participation/character_game_action.dart';
import 'package:peijianche_app/games/participation/character_participation_director.dart';
import 'package:peijianche_app/games/registry/mini_game_registry.dart';
import 'package:peijianche_app/games/services/game_action_pipeline.dart';
import 'package:peijianche_app/games/storage/game_session_storage_service.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_character_agent_view_builder.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_character_participation_adapter.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_engine.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_models.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_puzzle_registry.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_semantic_judge.dart';
import 'package:peijianche_app/pages/peilink/games/game_room_page.dart';
import 'package:peijianche_app/platform/storage/native_platform_storage.dart';
import 'package:peijianche_app/services/peilink_theme_service.dart';
import 'package:peijianche_app/widgets/theme/peilink_theme_scope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  MiniGameRegistry.instance;

  final alarm = TurtleSoupPuzzleRegistry.byId('silent_alarm');
  final ticket = TurtleSoupPuzzleRegistry.byId('last_train_ticket');
  final library = TurtleSoupPuzzleRegistry.byId('late_library');

  TurtleSoupState stateFor(TurtleSoupPuzzle puzzle) => TurtleSoupState(
    puzzleId: puzzle.id,
    title: puzzle.title,
    surface: puzzle.surface,
    truth: puzzle.truth,
    hints: puzzle.hints,
    phase: TurtleSoupPhase.questioning,
  );

  GameSession sessionFor(
    TurtleSoupPuzzle puzzle, {
    String sessionId = 'soup-judge',
    GameHost host = const GameHost.system(),
    List<GameParticipant> extraParticipants = const [],
    List<GameMessage> messages = const [],
  }) => GameSession(
    sessionId: sessionId,
    gameId: MiniGameRegistry.turtleSoupId,
    createdAt: DateTime(2026, 9, 20, 4),
    updatedAt: DateTime(2026, 9, 20, 4),
    status: GameSessionStatus.playing,
    host: host,
    participants: [
      const GameParticipant(
        participantId: 'user:1',
        type: GameParticipantType.user,
        displayName: '我',
      ),
      ...extraParticipants,
    ],
    gameState: stateFor(puzzle),
    messages: messages,
  );

  GameAction ask(String text, {String actor = 'user:1'}) => GameAction(
    type: GameActionType.custom,
    actorParticipantId: actor,
    payload: {'kind': 'question', 'text': text},
  );

  Future<GameMessage> answerOf(
    TurtleSoupEngine engine,
    GameSession session,
    String question, {
    String actor = 'user:1',
  }) async {
    final result = await engine.handleUserAction(
      session,
      ask(question, actor: actor),
    );
    expect(result.isSuccess, isTrue, reason: question);
    return result.value!.last.message!;
  }

  group('deterministic-first', () {
    test('unambiguous keyword rules answer without any model call', () async {
      final judge = _RecordingJudge(
        question: (value) =>
            throw StateError('judge should not be called: $value'),
      );
      final engine = TurtleSoupEngine(semanticJudge: judge);
      final session = sessionFor(library);

      final yes = await answerOf(engine, session, '她是在帮忙检查闭馆吗？');
      final no = await answerOf(engine, session, '她是因为偷书被惩罚吗？');
      final irrelevant = await answerOf(engine, session, '这和早餐有关吗？');

      expect(yes.content, TurtleSoupJudgment.yes.canonicalText);
      expect(no.content, TurtleSoupJudgment.no.canonicalText);
      expect(irrelevant.content, TurtleSoupJudgment.irrelevant.canonicalText);
      expect(judge.calls, 0);
    });

    test('conflicting deterministic premises defer to the judge', () async {
      final judge = _RecordingJudge(
        question: (_) => Future.value(TurtleSoupJudgment.no),
      );
      final engine = TurtleSoupEngine(semanticJudge: judge);
      final result = await engine.handleUserAction(
        sessionFor(library),
        ask('她是因为偷书被惩罚，还是闭馆后帮忙？'),
      );
      expect(judge.calls, 1);
      expect(
        result.value!.last.message!.content,
        TurtleSoupJudgment.no.canonicalText,
      );
    });
  });

  group('real device questions', () {
    test('specific alarm questions stop falling into UNKNOWN', () async {
      // 真机反馈的原话，判定来自测试用权威汤底，而不是关键词完全匹配。
      final judge = _RecordingJudge(
        question: (value) => Future.value(switch (value) {
          '警报是不是通过视觉信号触发的？' => TurtleSoupJudgment.yes,
          '是不是只有特定身份的人才能识别的视觉信号？' => TurtleSoupJudgment.partial,
          '警报触发是不是展厅里的灯光异常？' => TurtleSoupJudgment.no,
          '今天保安午饭吃了什么？' => TurtleSoupJudgment.irrelevant,
          _ => null,
        }),
      );
      final engine = TurtleSoupEngine(semanticJudge: judge);
      final session = sessionFor(alarm);

      expect(
        (await answerOf(engine, session, '警报是不是通过视觉信号触发的？')).content,
        TurtleSoupJudgment.yes.canonicalText,
      );
      expect(
        (await answerOf(engine, session, '是不是只有特定身份的人才能识别的视觉信号？')).content,
        TurtleSoupJudgment.partial.canonicalText,
      );
      expect(
        (await answerOf(engine, session, '警报触发是不是展厅里的灯光异常？')).content,
        TurtleSoupJudgment.no.canonicalText,
      );
      expect(
        (await answerOf(engine, session, '今天保安午饭吃了什么？')).content,
        TurtleSoupJudgment.irrelevant.canonicalText,
      );
      expect(judge.calls, 4);
      expect(judge.requests.first.puzzle.id, alarm.id);
      expect(judge.requests.first.puzzle.truth, alarm.truth);
      expect(
        judge.requests.first.puzzle.requiredTruthPoints,
        alarm.requiredTruthPoints,
      );
      expect(judge.requests.first.question, '警报是不是通过视觉信号触发的？');
    });

    test('specific ticket questions get semantic verdicts', () async {
      final judge = _RecordingJudge(
        question: (value) => Future.value(switch (value) {
          '这张车票是用于纪念用途吗？' => TurtleSoupJudgment.no,
          '车票的价值和站台某个特定标识有关吗？' => TurtleSoupJudgment.partial,
          _ => null,
        }),
      );
      final engine = TurtleSoupEngine(semanticJudge: judge);
      final session = sessionFor(ticket);

      expect(
        (await answerOf(engine, session, '这张车票是用于纪念用途吗？')).content,
        TurtleSoupJudgment.no.canonicalText,
      );
      expect(
        (await answerOf(engine, session, '车票的价值和站台某个特定标识有关吗？')).content,
        TurtleSoupJudgment.partial.canonicalText,
      );
      expect(judge.calls, 2);
    });

    test('every judgment maps to its own canonical wording', () {
      final canonicals = {
        for (final judgment in TurtleSoupJudgment.values)
          judgment: judgment.canonicalText,
      };
      expect(canonicals.values.toSet(), hasLength(5));
      expect(canonicals[TurtleSoupJudgment.yes], '是的。');
      expect(canonicals[TurtleSoupJudgment.no], '不是。');
      expect(canonicals[TurtleSoupJudgment.irrelevant], contains('无关'));
      expect(canonicals[TurtleSoupJudgment.partial], contains('可以把问题拆开问'));
      expect(canonicals[TurtleSoupJudgment.uncertain], contains('无法确定'));
      expect(
        canonicals[TurtleSoupJudgment.irrelevant],
        isNot(canonicals[TurtleSoupJudgment.uncertain]),
      );
      expect(
        canonicals[TurtleSoupJudgment.partial],
        isNot(canonicals[TurtleSoupJudgment.uncertain]),
      );
    });
  });

  group('structured judge', () {
    test('strict parser accepts only the judgment field', () {
      expect(
        parseTurtleSoupJudgment('{"judgment":"yes"}'),
        TurtleSoupJudgment.yes,
      );
      expect(
        parseTurtleSoupJudgment('```json\n{"judgment":"PARTIAL"}\n```'),
        TurtleSoupJudgment.partial,
      );
      for (final raw in [
        '',
        'not json',
        '{}',
        '[]',
        '{"judgment":""}',
        '{"judgment":"maybe"}',
        '{"judgment":"yes","text":"当然啦"}',
        '{"judgment":true}',
        '{"verdict":"yes"}',
      ]) {
        expect(parseTurtleSoupJudgment(raw), isNull, reason: 'raw=$raw');
      }
    });

    test('judge prompt carries authority and forbids host dialogue', () async {
      final gateway = _ScriptedGateway('{"judgment":"yes"}');
      final judge = ModelTurtleSoupSemanticJudge(gateway: gateway);
      final judgment = await judge.judge(
        TurtleSoupJudgeRequest(
          puzzle: alarm,
          question: '警报是不是通过视觉信号触发的？',
          recentPublicContext: const ['question user:1: 警报响过吗？'],
        ),
      );
      expect(judgment, TurtleSoupJudgment.yes);
      final prompt = gateway.messages
          .map((message) => message['content'].toString())
          .join('\n');
      expect(prompt, contains(alarm.truth));
      expect(prompt, contains('必须还原的真相要点'));
      expect(prompt, contains('闪光与手环震动'));
      expect(prompt, contains('警报是不是通过视觉信号触发的？'));
      expect(
        prompt,
        contains('{"judgment":"yes|no|irrelevant|partial|uncertain"}'),
      );
      expect(prompt, contains('不生成主持台词'));
      expect(gateway.messages.last['role'], 'user');
    });

    test('judge never produces host dialogue or state text', () async {
      final judge = ModelTurtleSoupSemanticJudge(
        gateway: _ScriptedGateway(
          jsonEncode({
            'judgment': 'partial',
            'text': '（笑）你还差一点点哦。',
            'truth': alarm.truth,
          }),
        ),
      );
      expect(
        await judge.judge(
          TurtleSoupJudgeRequest(puzzle: alarm, question: '视觉信号？'),
        ),
        isNull,
      );
    });
  });

  group('failure fallback', () {
    final failures = <String, SemanticJudgeModelGateway>{
      'malformed': _ScriptedGateway('not json'),
      'empty map': _ScriptedGateway('{}'),
      'empty output': _ScriptedGateway(''),
      'illegal enum': _ScriptedGateway('{"judgment":"probably"}'),
      'illegal extra field': _ScriptedGateway('{"judgment":"yes","hint":"闪光"}'),
      'provider exception': _ThrowingGateway(),
    };

    failures.forEach((name, gateway) {
      test(
        '$name falls back to canonical uncertain without breaking play',
        () async {
          final engine = TurtleSoupEngine(
            semanticJudge: ModelTurtleSoupSemanticJudge(gateway: gateway),
          );
          final message = await answerOf(
            engine,
            sessionFor(alarm),
            '警报是不是通过视觉信号触发的？',
          );
          expect(message.content, TurtleSoupJudgment.uncertain.canonicalText);
          expect(message.content, isNot(contains(alarm.truth)));
        },
      );
    });

    test('timeout falls back to canonical uncertain', () async {
      final completer = Completer<String>();
      final engine = TurtleSoupEngine(
        semanticJudge: ModelTurtleSoupSemanticJudge(
          gateway: _PendingGateway(completer.future),
          timeout: const Duration(milliseconds: 20),
        ),
      );
      final message = await answerOf(
        engine,
        sessionFor(alarm),
        '警报是不是通过视觉信号触发的？',
      );
      expect(message.content, TurtleSoupJudgment.uncertain.canonicalText);
      completer.complete('{"judgment":"yes"}');
    });

    test('missing provider keeps the deterministic fallback alive', () async {
      const engine = TurtleSoupEngine();
      final message = await answerOf(
        engine,
        sessionFor(alarm),
        '警报是不是通过视觉信号触发的？',
      );
      expect(message.content, TurtleSoupJudgment.uncertain.canonicalText);
    });
  });

  group('authority boundary', () {
    test('truth reaches the judge but never the player view', () async {
      final gateway = _ScriptedGateway('{"judgment":"yes"}');
      final engine = TurtleSoupEngine(
        semanticJudge: ModelTurtleSoupSemanticJudge(gateway: gateway),
      );
      final session = sessionFor(alarm);
      final result = await engine.handleUserAction(
        session,
        ask('警报是不是通过视觉信号触发的？'),
      );
      final messages = result.value!
          .map((event) => event.message)
          .whereType<GameMessage>()
          .toList();
      expect(messages, hasLength(2));
      expect(messages.first.type, GameMessageType.question);
      expect(messages.last.type, GameMessageType.answer);
      expect(messages.last.senderId, 'host');
      for (final message in messages) {
        expect(message.content, isNot(contains(alarm.truth)));
        expect(message.content, isNot(contains('听障专场')));
        expect(message.content, isNot(contains('judgment')));
      }
      expect(messages.last.content, TurtleSoupJudgment.yes.canonicalText);
      final prompt = gateway.messages
          .map((message) => message['content'].toString())
          .join('\n');
      expect(prompt, contains(alarm.truth));
    });

    test('judge cannot change puzzle, phase or counters', () async {
      final engine = TurtleSoupEngine(
        semanticJudge: _RecordingJudge(
          question: (_) => Future.value(TurtleSoupJudgment.yes),
        ),
      );
      final session = sessionFor(alarm);
      final result = await engine.handleUserAction(session, ask('视觉信号？'));
      final events = result.value!;
      expect(events, hasLength(3));
      final state = events.first.state! as TurtleSoupState;
      expect(events.first.type, GameEventType.stateChanged);
      expect(state.puzzleId, alarm.id);
      expect(state.truth, alarm.truth);
      expect(state.phase, TurtleSoupPhase.questioning);
      expect(state.questionCount, 1);
      expect(state.guessCount, 0);
      expect(state.usedHintCount, 0);
      expect(state.isSolved, isFalse);
    });
  });

  group('shared authoritative judgment', () {
    const character = GameParticipant(
      participantId: 'character:c1',
      type: GameParticipantType.character,
      displayName: '角色',
      characterId: 'c1',
    );

    test(
      'user question and character question use the same judge result',
      () async {
        final judge = _RecordingJudge(
          question: (_) => Future.value(TurtleSoupJudgment.partial),
        );
        final engine = TurtleSoupEngine(semanticJudge: judge);
        final session = sessionFor(alarm, extraParticipants: const [character]);

        final userAnswer = await answerOf(engine, session, '车票是纪念品吗？');
        final characterResult = await engine.handleCharacterAction(
          session,
          const CharacterGameAction(
            actorParticipantId: 'character:c1',
            type: CharacterGameActionType.askQuestion,
            content: '车票是纪念品吗？',
          ).toEngineAction(),
        );
        final answers = characterResult.value!
            .map((event) => event.message)
            .whereType<GameMessage>()
            .where((message) => message.type == GameMessageType.answer)
            .toList();
        expect(judge.calls, 2);
        expect(
          answers.single.content,
          TurtleSoupJudgment.partial.canonicalText,
        );
        expect(userAnswer.content, answers.single.content);
      },
    );

    test(
      'system host and character host consume the same judge result',
      () async {
        final judge = _RecordingJudge(
          question: (_) => Future.value(TurtleSoupJudgment.irrelevant),
        );
        final systemEngine = TurtleSoupEngine(semanticJudge: judge);
        final systemAnswer = await answerOf(
          systemEngine,
          sessionFor(alarm),
          '警报是什么颜色？',
        );

        final renderer = _EchoHostRenderer();
        final characterEngine = TurtleSoupEngine(
          semanticJudge: judge,
          hostRenderer: renderer,
        );
        final characterAnswer = await answerOf(
          characterEngine,
          sessionFor(alarm, host: const GameHost.character('c1')),
          '警报是什么颜色？',
        );

        expect(renderer.calls, 1);
        expect(
          renderer.lastRequest!.view.semanticResult.type,
          GameHostSemanticType.answerIrrelevant,
        );
        expect(
          characterAnswer.content,
          renderer.lastRequest!.view.semanticResult.canonicalText,
        );
        expect(characterAnswer.content, systemAnswer.content);
      },
    );
  });

  group('concurrency', () {
    test(
      'stale judge response cannot be written into another session',
      () async {
        final first = Completer<TurtleSoupJudgment?>();
        final second = Completer<TurtleSoupJudgment?>();
        final engine = TurtleSoupEngine(
          semanticJudge: _PendingJudge({
            '警报是不是通过视觉信号触发的？': first.future,
            '这张车票是用于纪念用途吗？': second.future,
          }),
        );
        final sessionA = sessionFor(alarm, sessionId: 'soup-a');
        final sessionB = sessionFor(ticket, sessionId: 'soup-b');

        final pendingA = engine.handleUserAction(
          sessionA,
          ask('警报是不是通过视觉信号触发的？'),
        );
        final pendingB = engine.handleUserAction(
          sessionB,
          ask('这张车票是用于纪念用途吗？'),
        );

        // B 先返回，A 后返回：A 的旧结果不能出现在 B 的会话里。
        second.complete(TurtleSoupJudgment.no);
        final resultB = await pendingB;
        first.complete(TurtleSoupJudgment.yes);
        final resultA = await pendingA;

        final messagesA = resultA.value!
            .map((event) => event.message)
            .whereType<GameMessage>()
            .toList();
        final messagesB = resultB.value!
            .map((event) => event.message)
            .whereType<GameMessage>()
            .toList();
        expect(
          messagesA.every((message) => message.sessionId == 'soup-a'),
          isTrue,
        );
        expect(
          messagesB.every((message) => message.sessionId == 'soup-b'),
          isTrue,
        );
        expect(messagesA.last.content, TurtleSoupJudgment.yes.canonicalText);
        expect(messagesB.last.content, TurtleSoupJudgment.no.canonicalText);
        expect(
          (resultA.value!.first.state! as TurtleSoupState).puzzleId,
          alarm.id,
        );
        expect(
          (resultB.value!.first.state! as TurtleSoupState).puzzleId,
          ticket.id,
        );
      },
    );

    test('action pipeline keeps submission order under async judges', () async {
      final pipeline = GameActionPipeline();
      final gate = Completer<void>();
      final order = <String>[];

      final first = pipeline.enqueue(() async {
        order.add('first-start');
        await gate.future;
        order.add('first-end');
      });
      final second = pipeline.enqueue(() async {
        order.add('second');
      });
      await Future<void>.delayed(Duration.zero);
      expect(order, ['first-start']);
      gate.complete();
      await first;
      await second;
      expect(order, ['first-start', 'first-end', 'second']);
      await pipeline.idle;
    });

    test('pipeline epoch rejects results from an invalidated action', () async {
      final pipeline = GameActionPipeline();
      final staleEpoch = pipeline.begin();
      final gate = Completer<void>();
      final applied = <String>[];
      final pending = pipeline.enqueue(() async {
        await gate.future;
        if (pipeline.accepts(staleEpoch)) applied.add('stale');
      });
      // 换题/离开房间：旧 round 立即失效。
      pipeline.invalidate();
      final freshEpoch = pipeline.begin();
      gate.complete();
      await pending;
      expect(applied, isEmpty);
      expect(pipeline.accepts(freshEpoch), isTrue);
      expect(pipeline.accepts(staleEpoch), isFalse);

      pipeline.dispose();
      final afterDispose = pipeline.begin();
      expect(pipeline.accepts(afterDispose), isFalse);
      await pipeline.idle;
    });
  });

  testWidgets('async judge answers on the room page without leaking truth', (
    tester,
  ) async {
    final root = await tester.runAsync(
      () => Directory.systemTemp.createTemp('soup_semantic_judge_'),
    );
    addTearDown(() => root!.delete(recursive: true));
    final judge = _RecordingJudge(
      question: (_) => Future.value(TurtleSoupJudgment.yes),
    );
    await tester.pumpWidget(
      PeiLinkThemeScope(
        controller: PeiLinkThemeController(),
        child: MaterialApp(
          home: GameRoomPage(
            session: sessionFor(alarm),
            storage: GameSessionStorageService(
              storage: NativePlatformStorage(root!.path),
            ),
            engine: TurtleSoupEngine(semanticJudge: judge),
            participationDirector: CharacterParticipationDirector(
              agent: const DeterministicCharacterGameAgent(
                actionType: CharacterGameActionType.pass,
              ),
              legality: const TurtleSoupCharacterParticipationAdapter(),
              viewBuilder: const TurtleSoupCharacterAgentViewBuilder(),
            ),
            bubbleDuration: const Duration(milliseconds: 40),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('turtle-soup-input')),
      '警报是不是通过视觉信号触发的？',
    );
    await tester.tap(find.byKey(const ValueKey('turtle-soup-send')));
    await tester.pump();
    await tester.pump();
    expect(judge.calls, 1);
    expect(find.text(TurtleSoupJudgment.yes.canonicalText), findsWidgets);
    expect(find.text(alarm.truth), findsNothing);
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.takeException(), isNull);
  });
}

class _RecordingJudge implements TurtleSoupSemanticJudge {
  _RecordingJudge({required this.question});
  final Future<TurtleSoupJudgment?> Function(String question) question;
  final List<TurtleSoupJudgeRequest> requests = [];
  int get calls => requests.length;

  @override
  Future<TurtleSoupJudgment?> judge(TurtleSoupJudgeRequest request) {
    requests.add(request);
    return question(request.question);
  }
}

class _PendingJudge implements TurtleSoupSemanticJudge {
  _PendingJudge(this.pending);
  final Map<String, Future<TurtleSoupJudgment?>> pending;

  @override
  Future<TurtleSoupJudgment?> judge(TurtleSoupJudgeRequest request) =>
      pending[request.question] ?? Future.value();
}

class _ScriptedGateway implements SemanticJudgeModelGateway {
  _ScriptedGateway(this.response);
  final String response;
  List<Map<String, dynamic>> messages = const [];

  @override
  Future<String> complete({
    required List<Map<String, dynamic>> messages,
  }) async {
    this.messages = messages;
    return response;
  }
}

class _ThrowingGateway implements SemanticJudgeModelGateway {
  @override
  Future<String> complete({
    required List<Map<String, dynamic>> messages,
  }) async => throw StateError('provider failed');
}

class _PendingGateway implements SemanticJudgeModelGateway {
  const _PendingGateway(this.future);
  final Future<String> future;

  @override
  Future<String> complete({required List<Map<String, dynamic>> messages}) =>
      future;
}

class _EchoHostRenderer implements CharacterHostResponseRenderer {
  int calls = 0;
  CharacterHostRenderRequest? lastRequest;

  @override
  Future<String> render(CharacterHostRenderRequest request) async {
    calls++;
    lastRequest = request;
    return request.view.semanticResult.canonicalText;
  }
}
