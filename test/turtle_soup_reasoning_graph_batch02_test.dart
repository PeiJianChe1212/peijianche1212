import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/games/models/game_models.dart';
import 'package:peijianche_app/games/participation/character_game_action.dart';
import 'package:peijianche_app/games/registry/mini_game_registry.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_engine.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_logic_profile.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_models.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_profile_registry.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_puzzle_registry.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_semantic_decision.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_semantic_judge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  MiniGameRegistry.instance;

  group('profile gate and deterministic boundary', () {
    test('the other nineteen puzzles keep the legacy judgment path', () async {
      final unprofiled = TurtleSoupPuzzleRegistry.puzzles
          .where(
            (puzzle) =>
                TurtleSoupProfileRegistry.findByPuzzleId(puzzle.id) == null,
          )
          .toList(growable: false);
      expect(unprofiled, hasLength(19));

      final judge = _LegacyJudge(TurtleSoupJudgment.no);
      final engine = TurtleSoupEngine(semanticJudge: judge);
      for (final puzzle in unprofiled) {
        final result = await engine.handleUserAction(
          _session(puzzle),
          _ask('这是一个没有确定性关键词的测试问题 ${puzzle.id}'),
        );
        expect(result.isSuccess, isTrue);
        expect(result.value!.last.message!.content, '不是。');
      }
      expect(judge.calls, 19);
    });

    for (final sample in const {
      'empty_cup_watermark': '空气中的水汽是否在杯子外壁冷凝',
      'midnight_greenhouse': '夜间补光是否帮助幼苗满足光照时长',
      'sealed_lunchbox': '负压是否导致柔性盒盖向内凹陷',
    }.entries) {
      test('${sample.key} unique guide returns a validated decision', () {
        final profile = TurtleSoupProfileRegistry.findByPuzzleId(sample.key)!;
        final decision = const TurtleSoupBoundaryDecisionMatcher().match(
          profile,
          '${sample.value}？',
        );
        expect(decision?.judgment, TurtleSoupJudgment.yes);
        expect(decision?.effects, isNotEmpty);
      });
    }

    test('ambiguous guide refuses deterministic guessing', () {
      final profile = _profile(
        guides: const [
          BoundaryGuide(
            id: 'b01',
            questionFamily: '设备是否正常',
            expectedJudgment: ProfileExpectedJudgment.yes,
            effects: [
              BoundaryEffect(
                type: BoundaryEffectType.confirmFact,
                targetId: 'f01',
              ),
            ],
          ),
          BoundaryGuide(
            id: 'b02',
            questionFamily: '设备是否正常？',
            expectedJudgment: ProfileExpectedJudgment.no,
            effects: [
              BoundaryEffect(
                type: BoundaryEffectType.confirmFact,
                targetId: 'f01',
              ),
            ],
          ),
        ],
      );
      expect(
        const TurtleSoupBoundaryDecisionMatcher().match(profile, '设备是否正常'),
        isNull,
      );
    });

    test('reverse polarity can confirm the same authoritative fact', () {
      final profile = _profile(
        guides: const [
          BoundaryGuide(
            id: 'b01',
            questionFamily: '设备坏了吗',
            expectedJudgment: ProfileExpectedJudgment.no,
            effects: [
              BoundaryEffect(
                type: BoundaryEffectType.confirmFact,
                targetId: 'f01',
              ),
            ],
          ),
          BoundaryGuide(
            id: 'b02',
            questionFamily: '设备其实正常',
            expectedJudgment: ProfileExpectedJudgment.yes,
            effects: [
              BoundaryEffect(
                type: BoundaryEffectType.confirmFact,
                targetId: 'f01',
              ),
            ],
          ),
        ],
      );
      final matcher = const TurtleSoupBoundaryDecisionMatcher();
      final broken = matcher.match(profile, '设备坏了吗？')!;
      final normal = matcher.match(profile, '设备其实正常？')!;
      expect(broken.judgment, TurtleSoupJudgment.no);
      expect(normal.judgment, TurtleSoupJudgment.yes);
      expect(broken.effects.single.targetId, 'f01');
      expect(normal.effects.single.targetId, 'f01');
    });
  });

  group('strict profiled judge output', () {
    final profile = TurtleSoupProfileRegistry.findByPuzzleId(
      'sealed_lunchbox',
    )!;

    test('valid judgment and effect survive', () {
      final decision = parseTurtleSoupSemanticDecision(
        '{"judgment":"NO","effects":[{"type":"confirmFact","ref":"f04"}]}',
        profile,
      );
      expect(decision?.judgment, TurtleSoupJudgment.no);
      expect(decision?.effects.single.targetId, 'f04');
    });

    for (final sample in <String, String>{
      'nonexistent ref':
          '{"judgment":"yes","effects":[{"type":"confirmFact","ref":"f99"}]}',
      'wrong node type':
          '{"judgment":"yes","effects":[{"type":"resolveEdge","ref":"f01"}]}',
      'conflicting effects':
          '{"judgment":"yes","effects":[{"type":"confirmFact","ref":"f01"},{"type":"partialFact","ref":"f01"}]}',
      'uncertain mutation':
          '{"judgment":"uncertain","effects":[{"type":"confirmFact","ref":"f01"}]}',
      'irrelevant fact mutation':
          '{"judgment":"irrelevant","effects":[{"type":"confirmFact","ref":"f01"}]}',
      'malformed effects': '{"judgment":"no","effects":{"type":"x"}}',
    }.entries) {
      test('${sample.key} retains judgment and drops all effects', () {
        final decision = parseTurtleSoupSemanticDecision(sample.value, profile);
        expect(decision, isNotNull);
        expect(decision!.effects, isEmpty);
      });
    }

    test('malformed whole response keeps the existing null fallback', () {
      expect(parseTurtleSoupSemanticDecision('not json', profile), isNull);
      expect(
        parseTurtleSoupSemanticDecision(
          '{"judgment":"maybe","effects":[]}',
          profile,
        ),
        isNull,
      );
    });

    test(
      'prompt exposes only legal IDs and asks for one structured result',
      () async {
        final gateway = _Gateway(
          jsonEncode({
            'judgment': 'yes',
            'effects': [
              {'type': 'confirmFact', 'ref': 'f01'},
            ],
          }),
        );
        final judge = ModelTurtleSoupSemanticJudge(gateway: gateway);
        final puzzle = TurtleSoupPuzzleRegistry.byId(profile.puzzleId);
        final decision = await judge.judgeDecision(
          TurtleSoupJudgeRequest(puzzle: puzzle, question: '盒盖柔软吗？'),
          profile,
        );
        expect(decision?.effects.single.targetId, 'f01');
        expect(gateway.calls, 1);
        final prompt = gateway.messages
            .map((item) => item['content'])
            .join('\n');
        expect(prompt, contains('合法事实节点'));
        expect(prompt, contains(profile.facts.first.statement));
        expect(prompt, contains('不得创建 ID'));
        expect(prompt, contains('必须返回全部适用 effects'));
        expect(prompt, contains('不要只返回 confirmFact'));
      },
    );
  });

  test(
    'user and character questions share decision and canonical behavior',
    () async {
      final judge = _DecisionJudge(
        const TurtleSoupSemanticDecision(
          judgment: TurtleSoupJudgment.partial,
          effects: [
            BoundaryEffect(
              type: BoundaryEffectType.partialFact,
              targetId: 'f01',
            ),
          ],
        ),
      );
      final engine = TurtleSoupEngine(semanticJudge: judge);
      final puzzle = TurtleSoupPuzzleRegistry.byId('empty_cup_watermark');
      final session = _session(puzzle, withCharacter: true);

      final user = await engine.handleUserAction(session, _ask('用户的模糊问题'));
      final character = await engine.handleCharacterAction(
        session,
        const CharacterGameAction(
          actorParticipantId: 'character:c1',
          type: CharacterGameActionType.askQuestion,
          content: '角色的模糊问题',
        ).toEngineAction(),
      );

      for (final result in [user, character]) {
        expect(result.isSuccess, isTrue);
        expect(result.value!.last.message!.content, '无法确定。可以把问题拆开问。');
        final next = result.value!.first.state! as TurtleSoupState;
        expect(next.questionCount, 1);
        expect(next.phase, TurtleSoupPhase.questioning);
      }
      expect(judge.decisionCalls, 2);
      expect(judge.legacyCalls, 0);
    },
  );
}

TurtleSoupLogicProfile _profile({required List<BoundaryGuide> guides}) =>
    TurtleSoupLogicProfile(
      version: 1,
      puzzleId: 'test_profile',
      facts: const [
        PuzzleFact(
          id: 'f01',
          statement: '设备本身正常。',
          publicSummary: '设备工作正常。',
          importance: PuzzleFactImportance.critical,
          category: '设备',
        ),
      ],
      causalEdges: const [],
      directions: const [],
      boundaryGuides: guides,
      solveCriteria: const SolveCriteria(requiredFactIds: ['f01']),
    );

GameSession _session(TurtleSoupPuzzle puzzle, {bool withCharacter = false}) =>
    GameSession(
      sessionId: 'batch02-${puzzle.id}',
      gameId: MiniGameRegistry.turtleSoupId,
      createdAt: DateTime(2026, 9, 22),
      updatedAt: DateTime(2026, 9, 22),
      status: GameSessionStatus.playing,
      host: const GameHost.system(),
      participants: [
        const GameParticipant(
          participantId: 'user:1',
          type: GameParticipantType.user,
          displayName: '我',
        ),
        if (withCharacter)
          const GameParticipant(
            participantId: 'character:c1',
            type: GameParticipantType.character,
            displayName: '角色一',
            characterId: 'c1',
          ),
      ],
      gameState: TurtleSoupState(
        puzzleId: puzzle.id,
        title: puzzle.title,
        surface: puzzle.surface,
        truth: puzzle.truth,
        hints: puzzle.hints,
        phase: TurtleSoupPhase.questioning,
      ),
    );

GameAction _ask(String text) => GameAction(
  type: GameActionType.custom,
  actorParticipantId: 'user:1',
  payload: {'kind': 'question', 'text': text},
);

class _LegacyJudge implements TurtleSoupSemanticJudge {
  _LegacyJudge(this.result);
  final TurtleSoupJudgment result;
  int calls = 0;

  @override
  Future<TurtleSoupJudgment?> judge(TurtleSoupJudgeRequest request) async {
    calls++;
    return result;
  }
}

class _DecisionJudge
    implements TurtleSoupSemanticJudge, TurtleSoupSemanticDecisionJudge {
  _DecisionJudge(this.result);
  final TurtleSoupSemanticDecision result;
  int legacyCalls = 0;
  int decisionCalls = 0;

  @override
  Future<TurtleSoupJudgment?> judge(TurtleSoupJudgeRequest request) async {
    legacyCalls++;
    return result.judgment;
  }

  @override
  Future<TurtleSoupSemanticDecision?> judgeDecision(
    TurtleSoupJudgeRequest request,
    TurtleSoupLogicProfile profile,
  ) async {
    decisionCalls++;
    return result;
  }
}

class _Gateway implements SemanticJudgeModelGateway {
  _Gateway(this.output);
  final String output;
  int calls = 0;
  List<Map<String, dynamic>> messages = const [];

  @override
  Future<String> complete({
    required List<Map<String, dynamic>> messages,
  }) async {
    calls++;
    this.messages = messages;
    return output;
  }
}
