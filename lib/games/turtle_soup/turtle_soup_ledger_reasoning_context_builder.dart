import '../participation/character_game_agent_view.dart';
import 'turtle_soup_logic_profile.dart';
import 'turtle_soup_reasoning_ledger.dart';
import 'turtle_soup_reasoning_frontier.dart';

class TurtleSoupLedgerReasoningContextBuilder {
  const TurtleSoupLedgerReasoningContextBuilder();

  CharacterGameReasoningContext build({
    required TurtleSoupLogicProfile profile,
    required PublicReasoningLedger ledger,
    List<String> recentCharacterQuestions = const [],
    List<String> recentGuesses = const [],
  }) {
    final view = ledger.toPublicView();
    final frontier = const TurtleSoupReasoningFrontierBuilder().build(
      profile: profile,
      ledger: ledger,
    );
    return CharacterGameReasoningContext(
      recentConfirmedDirections: List.unmodifiable([
        ...view.confirmedFacts.map((item) => item.text),
        ...view.resolvedEdges.map((item) => item.text),
      ]),
      recentRejectedDirections: List.unmodifiable(
        view.rejectedDirections.map((item) => item.text),
      ),
      recentPartialDirections: List.unmodifiable(
        view.partialFacts.map((item) => item.text),
      ),
      exhaustedDirections: List.unmodifiable(
        view.exhaustedDirections.map((item) => item.text),
      ),
      openQuestions: List.unmodifiable(
        view.openQuestions.map((item) => item.text),
      ),
      recentCharacterQuestions: List.unmodifiable(recentCharacterQuestions),
      recentGuesses: List.unmodifiable(recentGuesses),
      authoritativePublicLedger: true,
      worthContinuingDirections: frontier.worthContinuing,
      sufficientlyExploredDirections: frontier.sufficientlyExplored,
      readyToSynthesize: frontier.readyToSynthesize,
      actionableNextSteps: frontier.actionableNextSteps,
      publicHintClues: List.unmodifiable(
        view.publicHintClues.map((clue) => clue.text),
      ),
    );
  }
}
