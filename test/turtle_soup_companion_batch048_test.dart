import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_profile_registry.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_reasoning_ledger.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_reasoning_frontier.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_ledger_reasoning_context_builder.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_semantic_judge.dart';

void main() {
  for (final profile in TurtleSoupProfileRegistry.profiles) {
    test(
      '${profile.puzzleId}: legacy partial summaries never reach players',
      () {
        final ledger = PublicReasoningLedger.fromJson(
          PublicReasoningLedger(
            profileVersion: profile.version,
            partialFacts: [
              for (final fact in profile.facts)
                ReasoningLedgerEntry(
                  opaqueRef: fact.id,
                  publicText: fact.publicSummary,
                  provenanceMessageIds: const ['question-1', 'answer-1'],
                  updatedAtTurn: 1,
                ),
            ],
          ).toJson(),
        );
        expect(ledger.partialFacts, isNotEmpty);
        final projection = jsonEncode(ledger.toPublicView().toJson());
        final context = const TurtleSoupLedgerReasoningContextBuilder().build(
          profile: profile,
          ledger: ledger,
          recentCharacterQuestions: const ['这是我公开问过的问题？'],
        );
        expect(context.recentCharacterQuestions, contains('这是我公开问过的问题？'));
        expect(context.recentPartialDirections, isEmpty);
        for (final fact in profile.facts) {
          expect(projection, isNot(contains(fact.publicSummary)));
          expect(context.toPromptText(), isNot(contains(fact.publicSummary)));
          expect(context.toPromptText(), isNot(contains(fact.statement)));
          expect(context.toPromptText(), isNot(contains(fact.id)));
        }
        expect(context.toPromptText(), isNot(contains('尚未达到')));
      },
    );

    test('${profile.puzzleId}: empty ledger does not disclose directions', () {
      final frontier = const TurtleSoupReasoningFrontierBuilder().build(
        profile: profile,
        ledger: PublicReasoningLedger(profileVersion: profile.version),
      );
      expect(frontier.worthContinuing, isEmpty);
      expect(frontier.sufficientlyExplored, isEmpty);
      expect(frontier.actionableNextSteps, isEmpty);
      expect(frontier.readyToSynthesize, isFalse);
    });
  }

  test(
    'public partial is uncertainty, not closeness or a negative verdict',
    () {
      expect(
        TurtleSoupJudgment.partial.semanticType,
        isNot(TurtleSoupJudgment.no.semanticType),
      );
      expect(TurtleSoupJudgment.partial.canonicalText, contains('无法确定'));
      for (final text in ['接近', '关键条件', '方向对', '部分正确']) {
        expect(TurtleSoupJudgment.partial.canonicalText, isNot(contains(text)));
      }
      expect(TurtleSoupJudgment.yes.canonicalText, '是的。');
      expect(TurtleSoupJudgment.no.canonicalText, '不是。');
      expect(TurtleSoupJudgment.irrelevant.canonicalText, '无关。');
      expect(TurtleSoupJudgment.uncertain.canonicalText, '无法确定。');
    },
  );
}
