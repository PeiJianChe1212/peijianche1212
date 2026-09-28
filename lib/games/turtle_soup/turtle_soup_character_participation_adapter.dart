import '../models/game_models.dart';
import '../participation/character_game_action.dart';
import 'turtle_soup_models.dart';

class TurtleSoupCharacterParticipationAdapter
    implements CharacterGameActionLegality {
  const TurtleSoupCharacterParticipationAdapter();

  @override
  Set<CharacterGameActionType> allowedActions(
    GameSession session,
    GameParticipant participant,
  ) {
    final state = session.gameState;
    if (session.status != GameSessionStatus.playing ||
        state is! TurtleSoupState ||
        participant.type != GameParticipantType.character ||
        !session.participants.any(
          (item) =>
              item.participantId == participant.participantId &&
              item.characterId == participant.characterId,
        ) ||
        !{
          TurtleSoupPhase.questioning,
          TurtleSoupPhase.guessing,
        }.contains(state.phase)) {
      return const {CharacterGameActionType.pass};
    }
    return const {
      CharacterGameActionType.askQuestion,
      CharacterGameActionType.makeGuess,
      CharacterGameActionType.react,
      CharacterGameActionType.pass,
    };
  }
}
