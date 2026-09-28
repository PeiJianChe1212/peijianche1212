import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_ledger_reasoning_context_builder.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_logic_profile.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_logic_profile_validator.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_profile_registry.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_reasoning_frontier.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_reasoning_ledger.dart';

void main() {
  const frontierBuilder = TurtleSoupReasoningFrontierBuilder();

  test(
    'empty cup real-device progression stops low-value geometry digging',
    () {
      final profile = TurtleSoupProfileRegistry.findByPuzzleId(
        'empty_cup_watermark',
      )!;
      final ledger = _ledger(
        profile,
        confirmedFactIds: const ['f01', 'f03', 'f04'],
        resolvedEdgeIds: const ['e01', 'e02'],
        rejectedDirectionIds: const ['d05'],
      );
      final frontier = frontierBuilder.build(profile: profile, ledger: ledger);
      final context = const TurtleSoupLedgerReasoningContextBuilder().build(
        profile: profile,
        ledger: ledger,
      );
      final prompt = context.toPromptText();

      expect(frontier.readyToSynthesize, isTrue);
      expect(frontier.worthContinuing, isEmpty);
      expect(
        frontier.sufficientlyExplored,
        containsAll(['水迹来源与冷凝形成机制的公开信息已经足够。', '冷凝水到达桌面形成水迹的过程已经足够清楚。']),
      );
      expect(
        context.recentRejectedDirections,
        contains('杯底具体的凹槽、凸起或锥形结构不是解释水迹的必要条件。'),
      );
      expect(prompt, contains('公开记录支持尝试综合解释，但不要求现在 Guess'));
      expect(prompt, isNot(contains('仍是值得继续调查')));
      expect(prompt, isNot(contains('hidden')));
      for (final ref in ['f01', 'f03', 'f04', 'e01', 'e02', 'd05']) {
        expect(prompt, isNot(contains(ref)));
      }
    },
  );

  test('empty cup with only cold cup keeps useful directions open', () {
    final profile = TurtleSoupProfileRegistry.findByPuzzleId(
      'empty_cup_watermark',
    )!;
    final frontier = frontierBuilder.build(
      profile: profile,
      ledger: _ledger(profile, confirmedFactIds: const ['f01']),
    );
    expect(frontier.readyToSynthesize, isFalse);
    expect(frontier.worthContinuing, contains('杯子此前处于低温环境。'));
    expect(frontier.sufficientlyExplored, isEmpty);
  });

  test('empty cup partial condensation remains refinable', () {
    final profile = TurtleSoupProfileRegistry.findByPuzzleId(
      'empty_cup_watermark',
    )!;
    final frontier = frontierBuilder.build(
      profile: profile,
      ledger: _ledger(
        profile,
        confirmedFactIds: const ['f01'],
        partialFactIds: const ['f03'],
      ),
    );
    expect(frontier.readyToSynthesize, isFalse);
    expect(frontier.worthContinuing, contains('杯子此前处于低温环境。'));
    expect(
      frontier.sufficientlyExplored,
      isNot(contains('水迹来源与冷凝形成机制的公开信息已经足够。')),
    );
  });

  for (final puzzleId in const [
    'empty_cup_watermark',
    'midnight_greenhouse',
    'sealed_lunchbox',
  ]) {
    test('$puzzleId has safe worth, sufficient and synthesis states', () {
      final profile = TurtleSoupProfileRegistry.findByPuzzleId(puzzleId)!;
      final emptyFrontier = frontierBuilder.build(
        profile: profile,
        ledger: PublicReasoningLedger(profileVersion: profile.version),
      );
      expect(emptyFrontier.worthContinuing, isEmpty);
      expect(emptyFrontier.sufficientlyExplored, isEmpty);
      expect(emptyFrontier.readyToSynthesize, isFalse);

      final complete = _ledger(
        profile,
        confirmedFactIds: profile.solveCriteria.requiredFactIds,
        resolvedEdgeIds: profile.solveCriteria.requiredEdgeIds,
      );
      final completedFrontier = frontierBuilder.build(
        profile: profile,
        ledger: complete,
      );
      expect(completedFrontier.sufficientlyExplored, isNotEmpty);
      expect(completedFrontier.readyToSynthesize, isTrue);

      final publicText = [
        ...emptyFrontier.worthContinuing,
        ...completedFrontier.sufficientlyExplored,
      ].join('\n');
      for (final fact in profile.facts) {
        expect(publicText, isNot(contains(fact.statement)));
      }
      for (final direction in profile.directions) {
        expect(publicText, isNot(contains(direction.hiddenDescription)));
      }
      expect(publicText, isNot(matches(RegExp(r'\b[fedb]\d{2,}\b'))));
    });
  }

  test('pilot sufficient wording never asks the player to keep digging', () {
    for (final profile in TurtleSoupProfileRegistry.profiles) {
      for (final direction in profile.directions.where(
        (item) => item.kind == ReasoningDirectionKind.validBranch,
      )) {
        expect(direction.publicSufficientSummary, isNotEmpty);
        expect(direction.publicSufficientSummary, isNot(contains('继续调查')));
        expect(direction.publicSufficientSummary, isNot(contains('仍需探索')));
        expect(direction.publicSufficientSummary, isNot(contains('仍是有效')));
      }
    }
  });

  test('validator rejects incomplete valid-branch frontier metadata', () {
    const profile = TurtleSoupLogicProfile(
      version: 1,
      puzzleId: 'invalid-frontier',
      facts: [
        PuzzleFact(
          id: 'f01',
          statement: '隐藏事实',
          publicSummary: '公开事实',
          importance: PuzzleFactImportance.critical,
          category: '测试',
        ),
      ],
      causalEdges: [],
      directions: [
        ReasoningDirection(
          id: 'd01',
          hiddenDescription: '隐藏方向',
          publicRejectedSummary: '排除文案',
          relatedFactIds: ['f01'],
          kind: ReasoningDirectionKind.validBranch,
        ),
      ],
      boundaryGuides: [],
      solveCriteria: SolveCriteria(requiredFactIds: ['f01']),
    );
    final errors = const TurtleSoupLogicProfileValidator()
        .validate(profile)
        .errors
        .join('\n');
    expect(errors, contains('publicActiveSummary is empty'));
    expect(errors, contains('publicSufficientSummary is empty'));
    expect(errors, contains('has no sufficiency criteria'));
  });

  test(
    'reasoning context renders frontier priorities without schema changes',
    () {
      final profile = TurtleSoupProfileRegistry.findByPuzzleId(
        'empty_cup_watermark',
      )!;
      final context = const TurtleSoupLedgerReasoningContextBuilder().build(
        profile: profile,
        ledger: _ledger(
          profile,
          confirmedFactIds: const ['f01', 'f03', 'f04'],
          resolvedEdgeIds: const ['e01', 'e02'],
        ),
      );
      expect(context.worthContinuingDirections, isEmpty);
      expect(context.sufficientlyExploredDirections, hasLength(2));
      expect(context.readyToSynthesize, isTrue);
    },
  );
}

PublicReasoningLedger _ledger(
  TurtleSoupLogicProfile profile, {
  List<String> confirmedFactIds = const [],
  List<String> partialFactIds = const [],
  List<String> resolvedEdgeIds = const [],
  List<String> rejectedDirectionIds = const [],
}) => PublicReasoningLedger(
  profileVersion: profile.version,
  confirmedFacts: confirmedFactIds
      .map(
        (id) => ReasoningLedgerEntry(
          opaqueRef: id,
          publicText: profile.facts
              .firstWhere((item) => item.id == id)
              .publicSummary,
          provenanceMessageIds: const ['q', 'a'],
          updatedAtTurn: 1,
        ),
      )
      .toList(),
  partialFacts: partialFactIds
      .map(
        (id) => ReasoningLedgerEntry(
          opaqueRef: id,
          publicText: profile.facts
              .firstWhere((item) => item.id == id)
              .publicSummary,
          provenanceMessageIds: const ['q', 'a'],
          updatedAtTurn: 1,
        ),
      )
      .toList(),
  resolvedEdges: resolvedEdgeIds
      .map(
        (id) => ReasoningLedgerEntry(
          opaqueRef: id,
          publicText: profile.causalEdges
              .firstWhere((item) => item.id == id)
              .publicSummary,
          provenanceMessageIds: const ['q', 'a'],
          updatedAtTurn: 1,
        ),
      )
      .toList(),
  rejectedDirections: rejectedDirectionIds
      .map(
        (id) => ReasoningLedgerEntry(
          opaqueRef: id,
          publicText: profile.directions
              .firstWhere((item) => item.id == id)
              .publicRejectedSummary,
          provenanceMessageIds: const ['q', 'a'],
          updatedAtTurn: 1,
        ),
      )
      .toList(),
);
