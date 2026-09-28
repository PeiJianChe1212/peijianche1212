import 'turtle_soup_logic_profile.dart';
import 'turtle_soup_reasoning_ledger.dart';
import 'turtle_soup_semantic_decision.dart';

class TurtleSoupReasoningReducer {
  const TurtleSoupReasoningReducer();

  PublicReasoningLedger reduce({
    required PublicReasoningLedger current,
    required TurtleSoupSemanticDecision decision,
    required String question,
    required String canonicalAnswer,
    required List<String> provenanceMessageIds,
    required int currentTurn,
    required TurtleSoupLogicProfile profile,
  }) {
    if (decision.effects.isEmpty) return current;

    var confirmed = [...current.confirmedFacts];
    var partial = [...current.partialFacts];
    var rejected = [...current.rejectedDirections];
    var resolved = [...current.resolvedEdges];

    for (final effect in decision.effects) {
      switch (effect.type) {
        case BoundaryEffectType.confirmFact:
          final fact = _fact(profile, effect.targetId);
          if (fact == null) continue;
          partial.removeWhere((item) => item.opaqueRef == fact.id);
          confirmed = _upsert(
            confirmed,
            _entry(
              existing: _find(confirmed, fact.id),
              opaqueRef: fact.id,
              publicText: fact.publicSummary,
              provenanceMessageIds: provenanceMessageIds,
              currentTurn: currentTurn,
            ),
          );
        case BoundaryEffectType.partialFact:
          final fact = _fact(profile, effect.targetId);
          if (fact == null ||
              confirmed.any((item) => item.opaqueRef == fact.id)) {
            continue;
          }
          partial = _upsert(
            partial,
            _entry(
              existing: _find(partial, fact.id),
              opaqueRef: fact.id,
              publicText: fact.publicSummary,
              provenanceMessageIds: provenanceMessageIds,
              currentTurn: currentTurn,
            ),
          );
        case BoundaryEffectType.resolveEdge:
          final edge = _edge(profile, effect.targetId);
          if (edge == null) continue;
          resolved = _upsert(
            resolved,
            _entry(
              existing: _find(resolved, edge.id),
              opaqueRef: edge.id,
              publicText: edge.publicSummary,
              provenanceMessageIds: provenanceMessageIds,
              currentTurn: currentTurn,
            ),
          );
        case BoundaryEffectType.rejectDirection:
          final direction = _direction(profile, effect.targetId);
          if (direction == null) continue;
          rejected = _upsert(
            rejected,
            _entry(
              existing: _find(rejected, direction.id),
              opaqueRef: direction.id,
              publicText: direction.publicRejectedSummary,
              provenanceMessageIds: provenanceMessageIds,
              currentTurn: currentTurn,
            ),
          );
        case BoundaryEffectType.exhaustDirection:
          // Exhaustion is derived below from authoritative graph state. A raw
          // effect cannot bypass the conservative completion rules.
          break;
      }
    }

    final intermediate = current.copyWith(
      confirmedFacts: _sorted(confirmed),
      partialFacts: _sorted(partial),
      rejectedDirections: _sorted(rejected),
      resolvedEdges: _sorted(resolved),
    );
    return intermediate.copyWith(
      exhaustedDirections: _calculateExhausted(
        ledger: intermediate,
        profile: profile,
        provenanceMessageIds: provenanceMessageIds,
        currentTurn: currentTurn,
      ),
    );
  }

  List<ReasoningLedgerEntry> _calculateExhausted({
    required PublicReasoningLedger ledger,
    required TurtleSoupLogicProfile profile,
    required List<String> provenanceMessageIds,
    required int currentTurn,
  }) {
    var result = <ReasoningLedgerEntry>[];
    final previous = ledger.exhaustedDirections;
    final confirmed = ledger.confirmedFacts
        .map((item) => item.opaqueRef)
        .toSet();
    final partial = ledger.partialFacts.map((item) => item.opaqueRef).toSet();
    final rejected = ledger.rejectedDirections
        .map((item) => item.opaqueRef)
        .toSet();
    final resolved = ledger.resolvedEdges.map((item) => item.opaqueRef).toSet();

    for (final direction in profile.directions) {
      var exhausted = false;
      if (direction.kind == ReasoningDirectionKind.misconception) {
        exhausted =
            rejected.contains(direction.id) &&
            direction.relatedFactIds.every((id) => !partial.contains(id));
      } else {
        final related = direction.relatedFactIds.toSet();
        final critical = profile.facts
            .where(
              (fact) =>
                  related.contains(fact.id) &&
                  fact.importance == PuzzleFactImportance.critical,
            )
            .map((fact) => fact.id)
            .toSet();
        final requiredEdges = profile.causalEdges
            .where(
              (edge) =>
                  edge.requiredForSolve &&
                  related.contains(edge.targetFactId) &&
                  edge.sourceFactIds.every(related.contains),
            )
            .map((edge) => edge.id)
            .toSet();
        exhausted =
            critical.isNotEmpty &&
            critical.every(confirmed.contains) &&
            critical.every((id) => !partial.contains(id)) &&
            requiredEdges.every(resolved.contains);
      }
      if (!exhausted) continue;
      result = _upsert(
        result,
        _entry(
          existing: _find(previous, direction.id),
          opaqueRef: direction.id,
          publicText: direction.kind == ReasoningDirectionKind.validBranch
              ? direction.publicSufficientSummary
              : direction.publicRejectedSummary,
          provenanceMessageIds: provenanceMessageIds,
          currentTurn: currentTurn,
        ),
      );
    }
    return _sorted(result);
  }

  static PuzzleFact? _fact(TurtleSoupLogicProfile profile, String id) =>
      profile.facts.where((item) => item.id == id).firstOrNull;

  static CausalEdge? _edge(TurtleSoupLogicProfile profile, String id) =>
      profile.causalEdges.where((item) => item.id == id).firstOrNull;

  static ReasoningDirection? _direction(
    TurtleSoupLogicProfile profile,
    String id,
  ) => profile.directions.where((item) => item.id == id).firstOrNull;

  static ReasoningLedgerEntry? _find(
    List<ReasoningLedgerEntry> entries,
    String id,
  ) => entries.where((item) => item.opaqueRef == id).firstOrNull;

  static ReasoningLedgerEntry _entry({
    required ReasoningLedgerEntry? existing,
    required String opaqueRef,
    required String publicText,
    required List<String> provenanceMessageIds,
    required int currentTurn,
  }) => ReasoningLedgerEntry(
    opaqueRef: opaqueRef,
    publicText: publicText,
    provenanceMessageIds: List.unmodifiable({
      ...?existing?.provenanceMessageIds,
      ...provenanceMessageIds.where((id) => id.trim().isNotEmpty),
    }),
    updatedAtTurn: currentTurn,
  );

  static List<ReasoningLedgerEntry> _upsert(
    List<ReasoningLedgerEntry> entries,
    ReasoningLedgerEntry entry,
  ) => [...entries.where((item) => item.opaqueRef != entry.opaqueRef), entry];

  static List<ReasoningLedgerEntry> _sorted(
    List<ReasoningLedgerEntry> entries,
  ) => List.unmodifiable(
    [...entries]
      ..sort((left, right) => left.opaqueRef.compareTo(right.opaqueRef)),
  );
}
