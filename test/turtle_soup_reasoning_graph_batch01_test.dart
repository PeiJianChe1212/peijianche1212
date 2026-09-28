import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_logic_profile.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_logic_profile_validator.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_profile_registry.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_puzzle_registry.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_reasoning_ledger.dart';

void main() {
  const validator = TurtleSoupLogicProfileValidator();

  test('three dormant pilot profiles pass every invariant', () {
    expect(TurtleSoupProfileRegistry.profiles, hasLength(3));
    for (final profile in TurtleSoupProfileRegistry.profiles) {
      final result = validator.validate(
        profile,
        expectedPuzzleId: profile.puzzleId,
      );
      expect(
        result.errors,
        isEmpty,
        reason: '${profile.puzzleId}: ${result.errors}',
      );
    }
  });

  test('fact edge direction and boundary ids must be unique', () {
    final base = validProfile();
    final duplicateFact = TurtleSoupLogicProfile(
      version: base.version,
      puzzleId: base.puzzleId,
      facts: [...base.facts, base.facts.first],
      causalEdges: base.causalEdges,
      directions: base.directions,
      boundaryGuides: base.boundaryGuides,
      solveCriteria: base.solveCriteria,
    );
    expect(
      validator.validate(duplicateFact).errors.join(' '),
      contains('fact ids must be unique'),
    );
  });

  test('semantic ids are rejected in every hidden node family', () {
    final base = validProfile();
    final invalid = TurtleSoupLogicProfile(
      version: 1,
      puzzleId: base.puzzleId,
      facts: [
        const PuzzleFact(
          id: 'alarm_normal',
          statement: 'hidden',
          publicSummary: 'public',
          importance: PuzzleFactImportance.critical,
          category: '设备',
        ),
      ],
      causalEdges: const [],
      directions: const [],
      boundaryGuides: const [],
      solveCriteria: const SolveCriteria(requiredFactIds: ['alarm_normal']),
    );
    expect(
      validator.validate(invalid).errors.join(' '),
      contains('is not opaque'),
    );
  });

  test('dangling fact references are rejected', () {
    final base = validProfile();
    final invalid = TurtleSoupLogicProfile(
      version: base.version,
      puzzleId: base.puzzleId,
      facts: base.facts,
      causalEdges: const [
        CausalEdge(
          id: 'e01',
          sourceFactIds: ['f99'],
          relation: CausalRelation.causes,
          targetFactId: 'f01',
          publicSummary: '公开因果',
          requiredForSolve: true,
        ),
      ],
      directions: base.directions,
      boundaryGuides: base.boundaryGuides,
      solveCriteria: base.solveCriteria,
    );
    expect(
      validator.validate(invalid).errors.join(' '),
      contains('references missing fact f99'),
    );
  });

  test('invalid solve criteria are rejected', () {
    final base = validProfile();
    final invalid = TurtleSoupLogicProfile(
      version: base.version,
      puzzleId: base.puzzleId,
      facts: base.facts,
      causalEdges: base.causalEdges,
      directions: base.directions,
      boundaryGuides: base.boundaryGuides,
      solveCriteria: const SolveCriteria(requiredFactIds: ['f99']),
    );
    final errors = validator.validate(invalid).errors.join(' ');
    expect(errors, contains('solve criteria references missing fact f99'));
    expect(errors, contains('critical fact f01'));
  });

  test('boundary effects must target a node of the matching type', () {
    final base = validProfile();
    final invalid = TurtleSoupLogicProfile(
      version: base.version,
      puzzleId: base.puzzleId,
      facts: base.facts,
      causalEdges: base.causalEdges,
      directions: base.directions,
      boundaryGuides: const [
        BoundaryGuide(
          id: 'b01',
          questionFamily: '错误引用',
          expectedJudgment: ProfileExpectedJudgment.yes,
          effects: [
            BoundaryEffect(
              type: BoundaryEffectType.confirmFact,
              targetId: 'd01',
            ),
          ],
        ),
        BoundaryGuide(
          id: 'b02',
          questionFamily: '排除误区',
          expectedJudgment: ProfileExpectedJudgment.no,
          effects: [
            BoundaryEffect(
              type: BoundaryEffectType.rejectDirection,
              targetId: 'd01',
            ),
          ],
        ),
      ],
      solveCriteria: base.solveCriteria,
    );
    expect(
      validator.validate(invalid).errors.join(' '),
      contains('confirmFact has invalid target d01'),
    );
  });

  test('required causal dependency cycles are rejected', () {
    final invalid = TurtleSoupLogicProfile(
      version: 1,
      puzzleId: 'cycle',
      facts: const [
        PuzzleFact(
          id: 'f01',
          statement: '甲',
          publicSummary: '甲已确认',
          importance: PuzzleFactImportance.critical,
          category: '测试',
        ),
        PuzzleFact(
          id: 'f02',
          statement: '乙',
          publicSummary: '乙已确认',
          importance: PuzzleFactImportance.critical,
          category: '测试',
        ),
      ],
      causalEdges: const [
        CausalEdge(
          id: 'e01',
          sourceFactIds: ['f01'],
          relation: CausalRelation.causes,
          targetFactId: 'f02',
          publicSummary: '甲导致乙',
          requiredForSolve: true,
        ),
        CausalEdge(
          id: 'e02',
          sourceFactIds: ['f02'],
          relation: CausalRelation.causes,
          targetFactId: 'f01',
          publicSummary: '乙导致甲',
          requiredForSolve: true,
        ),
      ],
      directions: const [],
      boundaryGuides: const [],
      solveCriteria: const SolveCriteria(
        requiredFactIds: ['f01', 'f02'],
        requiredEdgeIds: ['e01', 'e02'],
      ),
    );
    expect(
      validator.validate(invalid).errors,
      contains('required causal dependencies contain a cycle'),
    );
  });

  test('public projection contains neither hidden text nor opaque refs', () {
    final profile = TurtleSoupProfileRegistry.byPuzzleId(
      'empty_cup_watermark',
    )!;
    final ledger = PublicReasoningLedger(profileVersion: profile.version)
        .withConfirmedFact(
          const ReasoningLedgerEntry(
            opaqueRef: 'f01',
            publicText: '杯子此前处于低温环境。',
            provenanceMessageIds: ['m01', 'm02'],
            updatedAtTurn: 2,
          ),
        )
        .withRejectedDirection(
          const ReasoningLedgerEntry(
            opaqueRef: 'd02',
            publicText: '水迹不是杯内液体泄漏造成的。',
            provenanceMessageIds: ['m03', 'm04'],
            updatedAtTurn: 4,
          ),
        );
    final encoded = jsonEncode(ledger.toPublicView().toJson());
    expect(encoded, contains('杯子此前处于低温环境'));
    expect(encoded, isNot(contains('opaqueRef')));
    expect(encoded, isNot(contains('f01')));
    expect(encoded, isNot(contains('d02')));
    for (final fact in profile.facts) {
      expect(encoded, isNot(contains(fact.statement)));
    }
    for (final direction in profile.directions) {
      expect(encoded, isNot(contains(direction.hiddenDescription)));
    }
    expect(profile.toString(), isNot(contains(profile.facts.first.statement)));
  });

  test('ledger is immutable, upserts by opaque ref and round-trips JSON', () {
    final original = PublicReasoningLedger(profileVersion: 3);
    const first = ReasoningLedgerEntry(
      opaqueRef: 'f01',
      publicText: '旧公开文本',
      provenanceMessageIds: ['m01'],
      updatedAtTurn: 1,
    );
    const replacement = ReasoningLedgerEntry(
      opaqueRef: 'f01',
      publicText: '新公开文本',
      provenanceMessageIds: ['m01', 'm02'],
      updatedAtTurn: 2,
    );
    final updated = original
        .withConfirmedFact(first)
        .withConfirmedFact(replacement)
        .withOpenQuestion(
          const ReasoningLedgerEntry(
            opaqueRef: 'q01',
            publicText: '具体由什么造成？',
            provenanceMessageIds: ['m03'],
            updatedAtTurn: 3,
          ),
        );
    expect(original.confirmedFacts, isEmpty);
    expect(updated.confirmedFacts, hasLength(1));
    expect(updated.confirmedFacts.single.publicText, '新公开文本');
    final restored = PublicReasoningLedger.fromJson(
      jsonDecode(jsonEncode(updated.toJson())) as Map,
    );
    expect(restored.version, updated.version);
    expect(restored.profileVersion, 3);
    expect(restored.confirmedFacts.single.opaqueRef, 'f01');
    expect(restored.confirmedFacts.single.provenanceMessageIds, ['m01', 'm02']);
    expect(restored.openQuestions.single.publicText, '具体由什么造成？');
  });

  test('remaining nineteen puzzles stay registered without a profile', () {
    final profiledIds = TurtleSoupProfileRegistry.profiles
        .map((item) => item.puzzleId)
        .toSet();
    final legacy = TurtleSoupPuzzleRegistry.puzzles
        .where((puzzle) => !profiledIds.contains(puzzle.id))
        .toList();
    expect(legacy, hasLength(19));
    for (final puzzle in legacy) {
      expect(TurtleSoupProfileRegistry.byPuzzleId(puzzle.id), isNull);
      expect(TurtleSoupPuzzleRegistry.byId(puzzle.id), same(puzzle));
    }
  });
}

TurtleSoupLogicProfile validProfile() => const TurtleSoupLogicProfile(
  version: 1,
  puzzleId: 'valid',
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
      hiddenDescription: '错误方向',
      publicRejectedSummary: '该方向已排除',
      relatedFactIds: ['f01'],
      kind: ReasoningDirectionKind.misconception,
    ),
  ],
  boundaryGuides: [
    BoundaryGuide(
      id: 'b01',
      questionFamily: '典型问题',
      expectedJudgment: ProfileExpectedJudgment.no,
      effects: [
        BoundaryEffect(
          type: BoundaryEffectType.rejectDirection,
          targetId: 'd01',
        ),
      ],
    ),
  ],
  solveCriteria: SolveCriteria(requiredFactIds: ['f01']),
);
