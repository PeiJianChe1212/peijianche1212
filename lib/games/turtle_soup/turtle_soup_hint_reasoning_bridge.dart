import 'turtle_soup_logic_profile.dart';
import 'turtle_soup_reasoning_ledger.dart';

class TurtleSoupHintReasoningBridge {
  const TurtleSoupHintReasoningBridge();

  PublicReasoningLedger apply({
    required PublicReasoningLedger ledger,
    required TurtleSoupLogicProfile profile,
    required String publishedHint,
    required String messageId,
    required int turn,
  }) {
    if (messageId.isEmpty ||
        !profile.hintReasoning.any((item) => item.hintText == publishedHint)) {
      return ledger;
    }
    final previous = ledger.publicHintClues
        .where((item) => item.text == publishedHint)
        .firstOrNull;
    return ledger.copyWith(
      publicHintClues: [
        ...ledger.publicHintClues.where((item) => item.text != publishedHint),
        PublicReasoningClue(
          text: publishedHint,
          provenanceMessageIds: {
            ...?previous?.provenanceMessageIds,
            messageId,
          }.toList(),
          updatedAtTurn: turn,
        ),
      ],
    );
  }
}
