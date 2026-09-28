import 'dart:convert';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/games/models/game_models.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_engine.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_models.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_guess_decision.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_semantic_judge.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_profile_registry.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_semantic_decision.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_puzzle_registry.dart';

void main() {
  test('timeout and provider exception fail closed', () async {
    for (final gateway in [_FailureGateway(false), _FailureGateway(true)]) {
      final judge = ModelTurtleSoupSemanticJudge(
        gateway: gateway,
        timeout: const Duration(milliseconds: 1),
      );
      final verdict = await judge.judgeGuess(
        TurtleSoupGuessRequest(
          puzzle: TurtleSoupPuzzleRegistry.byId('empty_cup_watermark'),
          guess: '完整解释',
        ),
      );
      expect(verdict, isFalse);
      expect(gateway.calls, 1);
    }
  });
  test(
    'cup paraphrase, incomplete explanation and wrong source fixtures',
    () async {
      for (final sample in {
        '空气中的水汽遇到冷杯壁凝结，沿杯外流到底部形成水迹': true,
        '只说杯子很冷，所以有水': false,
        '杯内的水因为杯子很冷流到桌面': false,
      }.entries) {
        final gateway = _Gateway((messages) {
          final input = jsonDecode(messages.last['content'] as String) as Map;
          expect(input['guess'], sample.key);
          final ids = (input['criteria'] as Map).keys.toList();
          return jsonEncode({
            'solved': sample.value,
            'coverage': sample.value ? ids : [],
            'missing': sample.value ? [] : ids,
            'contradiction': false,
          });
        });
        final result =
            await TurtleSoupEngine(
              semanticJudge: ModelTurtleSoupSemanticJudge(gateway: gateway),
            ).handleUserAction(
              _session('empty_cup_watermark'),
              GameAction(
                type: GameActionType.custom,
                actorParticipantId: 'u',
                payload: {'kind': 'guess', 'text': sample.key},
              ),
            );
        expect(
          (result.value!.first.state as TurtleSoupState).isSolved,
          sample.value,
        );
      }
    },
  );
  const correct = {
    'empty_cup_watermark':
        '杯子此前处于低温环境，杯壁温度远低于室内空气，室内温暖湿润的空气接触冰冷杯壁后，水汽在杯外冷凝成水，这些冷凝水流到桌面，杯子拿开后留下水迹',
    'midnight_greenhouse':
        '白天日照不足，自动系统晚上为需要足够光照时长的热带小苗开植物灯补足光照，值班员远程看设备即可，不用进温室。',
    'sealed_lunchbox':
        '换气装置坏了使楼内持续负压，柔性密封盖因此内凹；同层压力传感器维护无法报警，研究员没开盒就观察盖子并据此确认上报楼内问题。',
  };
  for (final sample in correct.entries) {
    test(
      '${sample.key} semantic verdict controls engine, not phrase matching',
      () async {
        for (final accepted in [true, false]) {
          final gateway = _Gateway((messages) {
            final input = jsonDecode(messages.last['content'] as String) as Map;
            final ids = (input['criteria'] as Map).keys.toList();
            expect(messages.first['content'], contains('关键词堆砌'));
            return jsonEncode({
              'solved': accepted,
              'coverage': accepted ? ids : [],
              'missing': accepted ? [] : ids,
              'contradiction': !accepted,
            });
          });
          final engine = TurtleSoupEngine(
            semanticJudge: ModelTurtleSoupSemanticJudge(gateway: gateway),
          );
          final result = await engine.handleUserAction(
            _session(sample.key),
            GameAction(
              type: GameActionType.custom,
              actorParticipantId: 'u',
              payload: {
                'kind': 'guess',
                'text': accepted ? sample.value : '低温 冷凝 负压 补光，但这些都不是原因，水从杯内流出',
              },
            ),
          );
          expect(gateway.calls, 1);
          final state = result.value!.first.state as TurtleSoupState;
          expect(state.isSolved, accepted);
          expect(state.guessCount, 1);
          if (!accepted) {
            final reply = result.value!.last.message!.content;
            for (final p in TurtleSoupPuzzleRegistry.byId(
              sample.key,
            ).requiredTruthPoints) {
              expect(reply, isNot(contains(p)));
            }
          }
        }
      },
    );
    test(
      '${sample.key} compound question contract and typed directions',
      () async {
        final gateway = _Gateway((messages) {
          expect(
            messages.first['content'],
            contains('unsupported premise → YES'),
          );
          expect(messages.first['content'], contains('not A 不等于 B'));
          expect(messages.last['content'], contains('[validBranch]'));
          expect(messages.last['content'], contains('[misconception]'));
          return '{"judgment":"uncertain","effects":[]}';
        });
        final result = await ModelTurtleSoupSemanticJudge(gateway: gateway)
            .judgeDecision(
              TurtleSoupJudgeRequest(
                puzzle: TurtleSoupPuzzleRegistry.byId(sample.key),
                question: '是因为接触了桌面以外的某个低温物体才发生的吗？',
              ),
              TurtleSoupProfileRegistry.findByPuzzleId(sample.key)!,
            );
        expect(result!.judgment, TurtleSoupJudgment.uncertain);
        expect(result.effects, isEmpty);
        expect(gateway.calls, 1);
      },
    );
  }
  test('negative evidence never confirms unrelated positive facts', () {
    for (final pair in {
      'empty_cup_watermark': ['b03'],
      'midnight_greenhouse': ['b05'],
      'sealed_lunchbox': ['b07', 'b08'],
    }.entries) {
      final profile = TurtleSoupProfileRegistry.findByPuzzleId(pair.key)!;
      for (final id in pair.value) {
        final guide = profile.boundaryGuides.firstWhere((g) => g.id == id);
        final result = const TurtleSoupBoundaryDecisionMatcher().match(
          profile,
          guide.questionFamily,
        )!;
        expect(
          result.effects.every((e) => e.type.name == 'rejectDirection'),
          isTrue,
        );
      }
    }
  });
  test('malformed, fabricated coverage and contradiction fail closed', () {
    for (final raw in [
      'bad',
      '{}',
      '{"solved":true,"coverage":["f99"],"missing":[],"contradiction":false}',
      '{"solved":true,"coverage":["p1"],"missing":[],"contradiction":true}',
      '{"solved":true,"coverage":[],"missing":["p1"],"contradiction":false}',
    ]) {
      expect(parseTurtleSoupGuessDecision(raw, {'p1'}), isFalse);
    }
  });
  test(
    'unavailable and malformed judge record guess without awarding win',
    () async {
      for (final judge in <TurtleSoupSemanticJudge?>[
        null,
        ModelTurtleSoupSemanticJudge(gateway: _Gateway((_) => 'bad')),
      ]) {
        final result = await TurtleSoupEngine(semanticJudge: judge)
            .handleUserAction(
              _session('empty_cup_watermark'),
              GameAction(
                type: GameActionType.custom,
                actorParticipantId: 'u',
                payload: {'kind': 'guess', 'text': correct.values.first},
              ),
            );
        expect(
          (result.value!.first.state as TurtleSoupState).isSolved,
          isFalse,
        );
        expect(
          result.value!.where((e) => e.message?.type == GameMessageType.guess),
          hasLength(1),
        );
      }
    },
  );
}

GameSession _session(String id) {
  final p = TurtleSoupPuzzleRegistry.byId(id);
  return GameSession(
    sessionId: 'authority',
    gameId: 'turtle_soup',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    status: GameSessionStatus.playing,
    host: const GameHost.system(),
    participants: const [
      GameParticipant(
        participantId: 'u',
        type: GameParticipantType.user,
        displayName: '我',
      ),
    ],
    gameState: TurtleSoupState(
      puzzleId: p.id,
      title: p.title,
      surface: p.surface,
      truth: p.truth,
      hints: p.hints,
      phase: TurtleSoupPhase.questioning,
    ),
  );
}

class _Gateway implements SemanticJudgeModelGateway {
  _Gateway(this.answer);
  final String Function(List<Map<String, dynamic>>) answer;
  int calls = 0;
  @override
  Future<String> complete({
    required List<Map<String, dynamic>> messages,
  }) async {
    calls++;
    return answer(messages);
  }
}

class _FailureGateway implements SemanticJudgeModelGateway {
  _FailureGateway(this.throwError);
  final bool throwError;
  int calls = 0;
  @override
  Future<String> complete({required List<Map<String, dynamic>> messages}) {
    calls++;
    if (throwError) throw StateError('unavailable');
    return Completer<String>().future;
  }
}
