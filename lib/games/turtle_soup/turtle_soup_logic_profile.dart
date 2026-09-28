enum PuzzleFactImportance { critical, supporting }

enum CausalRelation { causes, enables, explains, prevents, occursBefore }

enum ReasoningDirectionKind { validBranch, misconception }

enum ProfileExpectedJudgment { yes, no, partial, irrelevant, uncertain }

enum BoundaryEffectType {
  confirmFact,
  partialFact,
  rejectDirection,
  resolveEdge,
  exhaustDirection,
}

class PuzzleFact {
  const PuzzleFact({
    required this.id,
    required this.statement,
    required this.publicSummary,
    required this.importance,
    required this.category,
  });

  final String id;
  final String statement;
  final String publicSummary;
  final PuzzleFactImportance importance;
  final String category;
}

class CausalEdge {
  const CausalEdge({
    required this.id,
    required this.sourceFactIds,
    required this.relation,
    required this.targetFactId,
    required this.publicSummary,
    this.requiredForSolve = false,
  });

  final String id;
  final List<String> sourceFactIds;
  final CausalRelation relation;
  final String targetFactId;
  final String publicSummary;
  final bool requiredForSolve;
}

class ReasoningDirection {
  const ReasoningDirection({
    required this.id,
    required this.hiddenDescription,
    required this.publicRejectedSummary,
    required this.relatedFactIds,
    required this.kind,
    this.publicActiveSummary = '',
    this.publicSufficientSummary = '',
    this.sufficiencyFactIds = const [],
    this.sufficiencyEdgeIds = const [],
  });

  final String id;
  final String hiddenDescription;
  final String publicRejectedSummary;
  final List<String> relatedFactIds;
  final ReasoningDirectionKind kind;
  final String publicActiveSummary;
  final String publicSufficientSummary;
  final List<String> sufficiencyFactIds;
  final List<String> sufficiencyEdgeIds;
}

class BoundaryEffect {
  const BoundaryEffect({required this.type, required this.targetId});

  final BoundaryEffectType type;
  final String targetId;
}

class BoundaryGuide {
  const BoundaryGuide({
    required this.id,
    required this.questionFamily,
    required this.expectedJudgment,
    this.effects = const [],
  });

  final String id;
  final String questionFamily;
  final ProfileExpectedJudgment expectedJudgment;
  final List<BoundaryEffect> effects;
}

class SolveCriteria {
  const SolveCriteria({
    required this.requiredFactIds,
    this.requiredEdgeIds = const [],
  });

  final List<String> requiredFactIds;
  final List<String> requiredEdgeIds;
}

/// Reviewed public clue. Exact hint binding prevents content/index drift.
class HintReasoningMetadata {
  const HintReasoningMetadata({required this.hintText});
  final String hintText;
}

/// Only reviewed wording is emitted; hidden facts are never paraphrased.
class ActionableReasoningRule {
  const ActionableReasoningRule({
    required this.directionId,
    required this.requiredHintTexts,
    required this.publicText,
  });
  final String directionId;
  final List<String> requiredHintTexts;
  final String publicText;
}

/// Hidden, Engine-authority puzzle material.
///
/// This type intentionally has no JSON projection and does not override
/// [toString]. It must never be passed to Character/UI/public-summary layers.
class TurtleSoupLogicProfile {
  const TurtleSoupLogicProfile({
    required this.version,
    required this.puzzleId,
    required this.facts,
    required this.causalEdges,
    required this.directions,
    required this.boundaryGuides,
    required this.solveCriteria,
    this.hintReasoning = const [],
    this.actionableRules = const [],
  });

  final int version;
  final String puzzleId;
  final List<PuzzleFact> facts;
  final List<CausalEdge> causalEdges;
  final List<ReasoningDirection> directions;
  final List<BoundaryGuide> boundaryGuides;
  final SolveCriteria solveCriteria;
  final List<HintReasoningMetadata> hintReasoning;
  final List<ActionableReasoningRule> actionableRules;
}
