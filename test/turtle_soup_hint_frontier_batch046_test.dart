import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/games/models/game_models.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_character_agent_view_builder.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_engine.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_models.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_profile_registry.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_puzzle_registry.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_reasoning_ledger.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_reasoning_frontier.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_ledger_reasoning_context_builder.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_semantic_decision.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_semantic_judge.dart';

void main() {
  for (final profile in TurtleSoupProfileRegistry.profiles) {
    test(
      '${profile.puzzleId}: published hints survive resume, gate actions and reset',
      () async {
        final puzzle = TurtleSoupPuzzleRegistry.byId(profile.puzzleId);
        expect(profile.hintReasoning.map((e) => e.hintText), puzzle.hints);
        var state = TurtleSoupState(
          puzzleId: puzzle.id,
          title: puzzle.title,
          surface: puzzle.surface,
          truth: puzzle.truth,
          hints: puzzle.hints,
          phase: TurtleSoupPhase.questioning,
          reasoningLedger: PublicReasoningLedger(
            profileVersion: profile.version,
          ),
        );
        final session = GameSession(
          sessionId: 'hint-test',
          gameId: 'turtle_soup',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          status: GameSessionStatus.playing,
          host: const GameHost.system(),
          participants: const [
            GameParticipant(
              participantId: 'user:1',
              type: GameParticipantType.user,
              displayName: '我',
            ),
          ],
          gameState: state,
        );
        const builder = TurtleSoupReasoningFrontierBuilder();
        expect(
          builder
              .build(profile: profile, ledger: state.reasoningLedger!)
              .actionableNextSteps,
          isEmpty,
        );
        for (var i = 0; i < puzzle.hints.length; i++) {
          final result = await const TurtleSoupEngine().handleUserAction(
            session.copyWith(gameState: state),
            const GameAction(
              type: GameActionType.custom,
              actorParticipantId: 'user:1',
              payload: {'kind': 'hint'},
            ),
          );
          expect(result.isSuccess, isTrue);
          final message = result.value!.last.message!;
          state = result.value!.first.state! as TurtleSoupState;
          expect(
            state.reasoningLedger!.publicHintClues.last.provenanceMessageIds,
            [message.id],
          );
          expect(
            state.reasoningLedger!.publicHintClues.map((e) => e.text),
            puzzle.hints.take(i + 1),
          );
          expect(state.reasoningLedger!.confirmedFacts, isEmpty);
          expect(state.reasoningLedger!.resolvedEdges, isEmpty);
          expect(state.questionCount, 0);
          expect(state.guessCount, 0);
          final restored = TurtleSoupState.fromJson(state.toJson());
          expect(
            restored.reasoningLedger!.toJson(),
            state.reasoningLedger!.toJson(),
          );
          final frontier = builder.build(
            profile: profile,
            ledger: restored.reasoningLedger!,
          );
          expect(frontier.actionableNextSteps, isNotEmpty);
          expect(frontier.readyToSynthesize, isFalse);
          final prompt = const TurtleSoupLedgerReasoningContextBuilder()
              .build(profile: profile, ledger: restored.reasoningLedger!)
              .toPromptText();
          expect(prompt, contains(puzzle.hints[i]));
          expect(prompt, isNot(matches(RegExp(r'\b[fedb]\d{2,}\b'))));
          for (final fact in profile.facts) {
            expect(prompt, isNot(contains(fact.statement)));
          }
        }
        ReasoningLedgerEntry entry(String id, String text) =>
            ReasoningLedgerEntry(
              opaqueRef: id,
              publicText: text,
              provenanceMessageIds: const ['q'],
              updatedAtTurn: 2,
            );
        final agedSession = session.copyWith(
          gameState: state,
          messages: [
            GameMessage(
              sessionId: session.sessionId,
              senderId: 'host',
              type: GameMessageType.hint,
              content: puzzle.hints.first,
            ),
            for (var i = 0; i < 25; i++)
              GameMessage(
                sessionId: session.sessionId,
                senderId: 'user:1',
                type: GameMessageType.question,
                content: '最近公开问题 $i',
              ),
          ],
        );
        final view = const TurtleSoupCharacterAgentViewBuilder().build(
          session: agedSession,
          actor: session.participants.first,
          allowedActions: {},
        );
        expect(
          view.visibleHistory.any((m) => m.type == GameMessageType.hint),
          isFalse,
        );
        expect(view.reasoningContext.publicHintClues, puzzle.hints);
        expect(view.reasoningContext.actionableNextSteps, isNotEmpty);
        final complete = state.reasoningLedger!.copyWith(
          confirmedFacts: profile.facts
              .where(
                (f) => profile.solveCriteria.requiredFactIds.contains(f.id),
              )
              .map((f) => entry(f.id, f.publicSummary))
              .toList(),
          resolvedEdges: profile.causalEdges
              .where(
                (e) => profile.solveCriteria.requiredEdgeIds.contains(e.id),
              )
              .map((e) => entry(e.id, e.publicSummary))
              .toList(),
        );
        final frontier = builder.build(profile: profile, ledger: complete);
        expect(frontier.readyToSynthesize, isTrue);
        expect(frontier.sufficientlyExplored, isNotEmpty);
        expect(frontier.actionableNextSteps, isEmpty);
        if (profile.puzzleId == 'empty_cup_watermark') {
          final incomplete = complete.copyWith(
            confirmedFacts: complete.confirmedFacts
                .where((f) => f.opaqueRef != 'f03')
                .toList(),
            resolvedEdges: complete.resolvedEdges
                .where((e) => e.opaqueRef != 'e01')
                .toList(),
          );
          final next = builder.build(profile: profile, ledger: incomplete);
          expect(next.readyToSynthesize, isFalse);
          expect(next.actionableNextSteps, contains('可以继续确认杯外水分究竟来自哪里。'));
          expect(next.actionableNextSteps.join(), contains('房间空气是否参与'));
          expect(next.actionableNextSteps.join(), isNot(contains('冷凝')));
          expect(
            next.actionableNextSteps.join(),
            isNot(matches(RegExp(r'\b[fe]\d{2}\b'))),
          );
        }
        final replay = await const TurtleSoupEngine().playAgain(
          session.copyWith(
            status: GameSessionStatus.finished,
            gameState: state.copyWith(phase: TurtleSoupPhase.finished),
          ),
        );
        expect(replay.isSuccess, isTrue);
        final fresh = replay.value!.gameState as TurtleSoupState;
        expect(fresh.usedHintCount, 0);
        expect(fresh.reasoningLedger?.publicHintClues ?? [], isEmpty);
      },
    );
  }
  test('unknown other-liquid history is uncertain without effects', () {
    final profile = TurtleSoupProfileRegistry.findByPuzzleId(
      'empty_cup_watermark',
    )!;
    final decision = const TurtleSoupBoundaryDecisionMatcher().match(
      profile,
      '杯子里装过除水以外的液体吗？',
    )!;
    expect(decision.judgment, TurtleSoupJudgment.uncertain);
    expect(decision.effects, isEmpty);
  });
  test('profiled judge grounding contract uses one completion', () async {
    final gateway = _GroundedGateway();
    final decision = await ModelTurtleSoupSemanticJudge(gateway: gateway)
        .judgeDecision(
          TurtleSoupJudgeRequest(
            puzzle: TurtleSoupPuzzleRegistry.byId('empty_cup_watermark'),
            question: '杯子过去是否盛放过其他饮品？',
          ),
          TurtleSoupProfileRegistry.findByPuzzleId('empty_cup_watermark')!,
        );
    expect(gateway.calls, 1);
    expect(decision!.judgment, TurtleSoupJudgment.uncertain);
    expect(decision.effects, isEmpty);
  });
}

class _GroundedGateway implements SemanticJudgeModelGateway {
  int calls = 0;
  @override
  Future<String> complete({
    required List<Map<String, dynamic>> messages,
  }) async {
    calls++;
    final system = messages.first['content'] as String;
    expect(system, contains('truth 未说明且无法可靠推出为 uncertain'));
    expect(system, contains('禁止“也有可能，所以 YES”'));
    return '{"judgment":"uncertain","effects":[]}';
  }
}
