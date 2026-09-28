import 'turtle_soup_logic_profile.dart';
import 'turtle_soup_semantic_judge.dart';

class TurtleSoupSemanticDecision {
  const TurtleSoupSemanticDecision({
    required this.judgment,
    this.effects = const [],
  });

  final TurtleSoupJudgment judgment;
  final List<BoundaryEffect> effects;
}

class TurtleSoupDecisionEffectValidator {
  const TurtleSoupDecisionEffectValidator();

  /// Runtime decisions use an all-or-nothing policy. A model cannot smuggle a
  /// valid effect beside an invalid or contradictory one.
  List<BoundaryEffect> validate({
    required TurtleSoupLogicProfile profile,
    required TurtleSoupJudgment judgment,
    required List<BoundaryEffect> effects,
  }) {
    if (effects.isEmpty) return const [];
    if (judgment == TurtleSoupJudgment.uncertain) return const [];

    final factIds = profile.facts.map((item) => item.id).toSet();
    final edgeIds = profile.causalEdges.map((item) => item.id).toSet();
    final directions = {
      for (final direction in profile.directions) direction.id: direction,
    };
    final seenTargets = <String, BoundaryEffectType>{};

    for (final effect in effects) {
      final targetIsValid = switch (effect.type) {
        BoundaryEffectType.confirmFact ||
        BoundaryEffectType.partialFact => factIds.contains(effect.targetId),
        BoundaryEffectType.resolveEdge => edgeIds.contains(effect.targetId),
        BoundaryEffectType.rejectDirection ||
        BoundaryEffectType.exhaustDirection => directions.containsKey(
          effect.targetId,
        ),
      };
      if (!targetIsValid) return const [];

      if (effect.type == BoundaryEffectType.rejectDirection &&
          directions[effect.targetId]?.kind !=
              ReasoningDirectionKind.misconception) {
        return const [];
      }
      if (judgment == TurtleSoupJudgment.partial &&
          effect.type != BoundaryEffectType.partialFact) {
        return const [];
      }
      if (judgment != TurtleSoupJudgment.partial &&
          effect.type == BoundaryEffectType.partialFact) {
        return const [];
      }
      if (judgment == TurtleSoupJudgment.irrelevant &&
          effect.type != BoundaryEffectType.rejectDirection &&
          effect.type != BoundaryEffectType.exhaustDirection) {
        return const [];
      }

      final previous = seenTargets[effect.targetId];
      if (previous != null && previous != effect.type) return const [];
      seenTargets[effect.targetId] = effect.type;
    }

    return List<BoundaryEffect>.unmodifiable(
      {
        for (final effect in effects)
          '${effect.type.name}:${effect.targetId}': effect,
      }.values,
    );
  }
}

class TurtleSoupBoundaryDecisionMatcher {
  const TurtleSoupBoundaryDecisionMatcher({
    this.effectValidator = const TurtleSoupDecisionEffectValidator(),
  });

  final TurtleSoupDecisionEffectValidator effectValidator;

  /// Deliberately exact after punctuation/spacing normalization. A family is
  /// not treated as a bag of fuzzy keywords; ambiguous matches defer to Judge.
  TurtleSoupSemanticDecision? match(
    TurtleSoupLogicProfile profile,
    String question,
  ) {
    final normalized = _normalize(question);
    if (normalized.isEmpty) return null;
    final matches = profile.boundaryGuides
        .where((guide) => _normalize(guide.questionFamily) == normalized)
        .toList(growable: false);
    if (matches.length != 1) return null;

    final guide = matches.single;
    final judgment = _judgment(guide.expectedJudgment);
    final effects = effectValidator.validate(
      profile: profile,
      judgment: judgment,
      effects: guide.effects,
    );
    if (effects.length != guide.effects.length) return null;
    return TurtleSoupSemanticDecision(judgment: judgment, effects: effects);
  }

  static TurtleSoupJudgment _judgment(ProfileExpectedJudgment value) =>
      TurtleSoupJudgment.values.byName(value.name);

  static String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[\s，。！？、,.!?；;：:]'), '');
}
