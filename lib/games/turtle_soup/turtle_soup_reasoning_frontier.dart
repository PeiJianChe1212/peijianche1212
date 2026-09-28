import 'turtle_soup_logic_profile.dart';
import 'turtle_soup_reasoning_ledger.dart';

/// Character-safe, fully derived reasoning priorities. It deliberately has no
/// opaque node references and is never persisted.
class TurtleSoupReasoningFrontier {
  const TurtleSoupReasoningFrontier({
    required this.worthContinuing,
    required this.sufficientlyExplored,
    required this.readyToSynthesize,
    this.actionableNextSteps = const [],
  });

  final List<String> worthContinuing;
  final List<String> sufficientlyExplored;
  final bool readyToSynthesize;
  final List<String> actionableNextSteps;
}

class TurtleSoupReasoningFrontierBuilder {
  const TurtleSoupReasoningFrontierBuilder();

  TurtleSoupReasoningFrontier build({
    required TurtleSoupLogicProfile profile,
    required PublicReasoningLedger ledger,
  }) {
    final confirmed = ledger.confirmedFacts
        .map((entry) => entry.opaqueRef)
        .toSet();
    final partial = ledger.partialFacts.map((entry) => entry.opaqueRef).toSet();
    final resolved = ledger.resolvedEdges
        .map((entry) => entry.opaqueRef)
        .toSet();
    final exhausted = ledger.exhaustedDirections
        .map((entry) => entry.opaqueRef)
        .toSet();
    final worthContinuing = <String>[];
    final sufficientlyExplored = <String>[];
    final activeDirectionIds = <String>{};

    for (final direction in profile.directions.where(
      (item) => item.kind == ReasoningDirectionKind.validBranch,
    )) {
      final sufficient =
          direction.sufficiencyFactIds.every(confirmed.contains) &&
          direction.sufficiencyEdgeIds.every(resolved.contains) &&
          direction.sufficiencyFactIds.every((id) => !partial.contains(id));
      if (sufficient) {
        if (direction.publicSufficientSummary.trim().isNotEmpty) {
          sufficientlyExplored.add(direction.publicSufficientSummary.trim());
        }
      } else if (!exhausted.contains(direction.id)) {
        // A static direction description may presuppose undiscovered facts.
        // Refer only to facts already published; hint-gated rules below remain
        // available even when no fact has been confirmed yet.
        worthContinuing.addAll(
          ledger.confirmedFacts
              .where(
                (entry) => direction.relatedFactIds.contains(entry.opaqueRef),
              )
              .map((entry) => entry.publicText),
        );
        activeDirectionIds.add(direction.id);
      }
    }

    final requiredFacts = profile.solveCriteria.requiredFactIds;
    final requiredEdges = profile.solveCriteria.requiredEdgeIds;
    final readyToSynthesize =
        requiredFacts.isNotEmpty &&
        requiredFacts.every(confirmed.contains) &&
        requiredEdges.every(resolved.contains) &&
        requiredFacts.every((id) => !partial.contains(id));

    return TurtleSoupReasoningFrontier(
      actionableNextSteps: List.unmodifiable(
        readyToSynthesize
            ? <String>[]
            : {
                for (final rule in profile.actionableRules)
                  if (activeDirectionIds.contains(rule.directionId) &&
                      rule.requiredHintTexts.isNotEmpty &&
                      rule.requiredHintTexts.every(
                        (text) => ledger.publicHintClues.any(
                          (clue) => clue.text == text,
                        ),
                      ))
                    rule.publicText,
              },
      ),
      worthContinuing: List.unmodifiable(worthContinuing.toSet()),
      sufficientlyExplored: List.unmodifiable(sufficientlyExplored),
      readyToSynthesize: readyToSynthesize,
    );
  }
}
