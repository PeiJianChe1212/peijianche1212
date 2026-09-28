import 'turtle_soup_logic_profile.dart';

class TurtleSoupLogicProfileValidationResult {
  const TurtleSoupLogicProfileValidationResult(this.errors);

  final List<String> errors;
  bool get isValid => errors.isEmpty;
}

class TurtleSoupLogicProfileValidator {
  const TurtleSoupLogicProfileValidator();

  static final RegExp _factId = RegExp(r'^f\d{2,}$');
  static final RegExp _edgeId = RegExp(r'^e\d{2,}$');
  static final RegExp _directionId = RegExp(r'^d\d{2,}$');
  static final RegExp _boundaryId = RegExp(r'^b\d{2,}$');

  TurtleSoupLogicProfileValidationResult validate(
    TurtleSoupLogicProfile profile, {
    String? expectedPuzzleId,
  }) {
    final errors = <String>[];
    if (profile.version <= 0) errors.add('profile version must be positive');
    if (profile.puzzleId.trim().isEmpty) errors.add('puzzleId is empty');
    if (expectedPuzzleId != null && profile.puzzleId != expectedPuzzleId) {
      errors.add('profile puzzleId does not match $expectedPuzzleId');
    }

    final factIds = profile.facts.map((item) => item.id).toSet();
    final edgeIds = profile.causalEdges.map((item) => item.id).toSet();
    final directionIds = profile.directions.map((item) => item.id).toSet();
    _validateIds(profile.facts.map((item) => item.id), _factId, 'fact', errors);
    _validateIds(
      profile.causalEdges.map((item) => item.id),
      _edgeId,
      'edge',
      errors,
    );
    _validateIds(
      profile.directions.map((item) => item.id),
      _directionId,
      'direction',
      errors,
    );
    _validateIds(
      profile.boundaryGuides.map((item) => item.id),
      _boundaryId,
      'boundary',
      errors,
    );
    final allIds = [
      ...profile.facts.map((item) => item.id),
      ...profile.causalEdges.map((item) => item.id),
      ...profile.directions.map((item) => item.id),
      ...profile.boundaryGuides.map((item) => item.id),
    ];
    if (allIds.toSet().length != allIds.length) {
      errors.add('profile ids must be globally unique');
    }

    for (final fact in profile.facts) {
      if (fact.statement.trim().isEmpty) {
        errors.add('${fact.id} hidden statement is empty');
      }
      if (fact.publicSummary.trim().isEmpty) {
        errors.add('${fact.id} publicSummary is empty');
      }
      if (fact.category.trim().isEmpty) {
        errors.add('${fact.id} category is empty');
      }
    }
    for (final edge in profile.causalEdges) {
      if (edge.publicSummary.trim().isEmpty) {
        errors.add('${edge.id} publicSummary is empty');
      }
      if (edge.sourceFactIds.isEmpty) {
        errors.add('${edge.id} has no source facts');
      }
      for (final sourceId in edge.sourceFactIds) {
        if (!factIds.contains(sourceId)) {
          errors.add('${edge.id} references missing fact $sourceId');
        }
      }
      if (!factIds.contains(edge.targetFactId)) {
        errors.add('${edge.id} references missing fact ${edge.targetFactId}');
      }
      if (edge.sourceFactIds.contains(edge.targetFactId)) {
        errors.add('${edge.id} directly depends on itself');
      }
    }
    for (final direction in profile.directions) {
      if (direction.hiddenDescription.trim().isEmpty) {
        errors.add('${direction.id} hiddenDescription is empty');
      }
      if (direction.kind == ReasoningDirectionKind.misconception &&
          direction.publicRejectedSummary.trim().isEmpty) {
        errors.add('${direction.id} publicRejectedSummary is empty');
      }
      if (direction.kind == ReasoningDirectionKind.validBranch) {
        if (direction.publicActiveSummary.trim().isEmpty) {
          errors.add(
            '${direction.id} valid branch publicActiveSummary is empty',
          );
        }
        if (direction.publicSufficientSummary.trim().isEmpty) {
          errors.add(
            '${direction.id} valid branch publicSufficientSummary is empty',
          );
        }
        if (direction.sufficiencyFactIds.isEmpty &&
            direction.sufficiencyEdgeIds.isEmpty) {
          errors.add(
            '${direction.id} valid branch has no sufficiency criteria',
          );
        }
      }
      if (direction.relatedFactIds.isEmpty) {
        errors.add('${direction.id} has no related facts');
      }
      for (final factId in direction.relatedFactIds) {
        if (!factIds.contains(factId)) {
          errors.add('${direction.id} references missing fact $factId');
        }
      }
      for (final factId in direction.sufficiencyFactIds) {
        if (!factIds.contains(factId)) {
          errors.add(
            '${direction.id} sufficiency references missing fact $factId',
          );
        } else if (!direction.relatedFactIds.contains(factId)) {
          errors.add(
            '${direction.id} sufficiency fact $factId is outside direction',
          );
        }
      }
      for (final edgeId in direction.sufficiencyEdgeIds) {
        if (!edgeIds.contains(edgeId)) {
          errors.add(
            '${direction.id} sufficiency references missing edge $edgeId',
          );
        }
      }
    }

    for (final id in profile.solveCriteria.requiredFactIds) {
      if (!factIds.contains(id)) {
        errors.add('solve criteria references missing fact $id');
      }
    }
    for (final id in profile.solveCriteria.requiredEdgeIds) {
      if (!edgeIds.contains(id)) {
        errors.add('solve criteria references missing edge $id');
      } else {
        final edge = profile.causalEdges.firstWhere((item) => item.id == id);
        if (!edge.requiredForSolve) {
          errors.add('solve criteria edge $id is not requiredForSolve');
        }
      }
    }
    for (final fact in profile.facts.where(
      (item) => item.importance == PuzzleFactImportance.critical,
    )) {
      if (!profile.solveCriteria.requiredFactIds.contains(fact.id)) {
        errors.add('critical fact ${fact.id} is absent from solve criteria');
      }
    }

    for (final guide in profile.boundaryGuides) {
      if (guide.questionFamily.trim().isEmpty) {
        errors.add('${guide.id} questionFamily is empty');
      }
      _validateBoundary(
        guide,
        factIds: factIds,
        edgeIds: edgeIds,
        directionIds: directionIds,
        directions: profile.directions,
        errors: errors,
      );
    }

    _validateRequiredCycles(profile, errors);
    final hints = profile.hintReasoning.map((item) => item.hintText).toSet();
    if (hints.length != profile.hintReasoning.length ||
        hints.any((text) => text.trim().isEmpty)) {
      errors.add('hint metadata must be nonempty and unique');
    }
    for (final rule in profile.actionableRules) {
      final direction = profile.directions
          .where((item) => item.id == rule.directionId)
          .firstOrNull;
      if (direction == null ||
          direction.kind != ReasoningDirectionKind.validBranch ||
          rule.publicText.trim().isEmpty ||
          rule.requiredHintTexts.isEmpty ||
          !rule.requiredHintTexts.every(hints.contains)) {
        errors.add('invalid actionable rule');
      }
    }
    _validateMisconceptions(profile, errors);
    return TurtleSoupLogicProfileValidationResult(List.unmodifiable(errors));
  }

  void _validateIds(
    Iterable<String> ids,
    RegExp format,
    String label,
    List<String> errors,
  ) {
    final values = ids.toList();
    if (values.toSet().length != values.length) {
      errors.add('$label ids must be unique');
    }
    for (final id in values) {
      if (!format.hasMatch(id)) errors.add('$label id $id is not opaque');
    }
  }

  void _validateBoundary(
    BoundaryGuide guide, {
    required Set<String> factIds,
    required Set<String> edgeIds,
    required Set<String> directionIds,
    required List<ReasoningDirection> directions,
    required List<String> errors,
  }) {
    if (guide.expectedJudgment == ProfileExpectedJudgment.uncertain &&
        guide.effects.isNotEmpty) {
      errors.add('${guide.id} uncertain judgment cannot mutate reasoning');
    }
    for (final effect in guide.effects) {
      final validTarget = switch (effect.type) {
        BoundaryEffectType.confirmFact ||
        BoundaryEffectType.partialFact => factIds.contains(effect.targetId),
        BoundaryEffectType.resolveEdge => edgeIds.contains(effect.targetId),
        BoundaryEffectType.rejectDirection ||
        BoundaryEffectType.exhaustDirection => directionIds.contains(
          effect.targetId,
        ),
      };
      if (!validTarget) {
        errors.add(
          '${guide.id} effect ${effect.type.name} has invalid target ${effect.targetId}',
        );
        continue;
      }
      if (effect.type == BoundaryEffectType.partialFact &&
          guide.expectedJudgment != ProfileExpectedJudgment.partial) {
        errors.add('${guide.id} partialFact requires partial judgment');
      }
      if (guide.expectedJudgment == ProfileExpectedJudgment.partial &&
          effect.type != BoundaryEffectType.partialFact) {
        errors.add('${guide.id} partial judgment has contradictory effect');
      }
      if (guide.expectedJudgment == ProfileExpectedJudgment.irrelevant &&
          {
            BoundaryEffectType.confirmFact,
            BoundaryEffectType.partialFact,
            BoundaryEffectType.resolveEdge,
          }.contains(effect.type)) {
        errors.add('${guide.id} irrelevant judgment confirms hidden logic');
      }
      if (effect.type == BoundaryEffectType.rejectDirection) {
        final direction = directions.firstWhere(
          (item) => item.id == effect.targetId,
        );
        if (direction.kind != ReasoningDirectionKind.misconception) {
          errors.add('${guide.id} rejects an authoritative valid branch');
        }
      }
    }
  }

  void _validateRequiredCycles(
    TurtleSoupLogicProfile profile,
    List<String> errors,
  ) {
    final adjacency = <String, Set<String>>{};
    for (final edge in profile.causalEdges.where(
      (item) => item.requiredForSolve,
    )) {
      for (final source in edge.sourceFactIds) {
        adjacency.putIfAbsent(source, () => <String>{}).add(edge.targetFactId);
      }
    }
    final visiting = <String>{};
    final visited = <String>{};
    bool visit(String id) {
      if (visiting.contains(id)) return true;
      if (!visited.add(id)) return false;
      visiting.add(id);
      for (final next in adjacency[id] ?? const <String>{}) {
        if (visit(next)) return true;
      }
      visiting.remove(id);
      return false;
    }

    if (profile.facts.any((fact) => visit(fact.id))) {
      errors.add('required causal dependencies contain a cycle');
    }
  }

  void _validateMisconceptions(
    TurtleSoupLogicProfile profile,
    List<String> errors,
  ) {
    final rejected = profile.boundaryGuides
        .expand((guide) => guide.effects)
        .where((effect) => effect.type == BoundaryEffectType.rejectDirection)
        .map((effect) => effect.targetId)
        .toSet();
    for (final direction in profile.directions.where(
      (item) => item.kind == ReasoningDirectionKind.misconception,
    )) {
      if (!rejected.contains(direction.id)) {
        errors.add(
          'misconception ${direction.id} has no authoritative rejection guide',
        );
      }
    }
  }
}
