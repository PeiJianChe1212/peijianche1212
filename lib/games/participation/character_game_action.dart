import '../models/game_models.dart';

enum CharacterGameActionType { askQuestion, makeGuess, react, pass }

class CharacterGameAction {
  const CharacterGameAction({
    required this.actorParticipantId,
    required this.type,
    this.content = '',
  });

  final String actorParticipantId;
  final CharacterGameActionType type;
  final String content;

  GameAction toEngineAction() => GameAction(
    type: GameActionType.custom,
    actorParticipantId: actorParticipantId,
    payload: {
      'kind': 'characterGameAction',
      'characterAction': type.name,
      if (content.trim().isNotEmpty) 'text': content.trim(),
    },
  );
}

abstract interface class CharacterGameActionLegality {
  Set<CharacterGameActionType> allowedActions(
    GameSession session,
    GameParticipant participant,
  );
}
