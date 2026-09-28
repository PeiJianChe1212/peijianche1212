import '../models/game_models.dart';

class GameRoomVisibility {
  const GameRoomVisibility._();

  static String? currentUserParticipantId(GameSession session) => session
      .participants
      .where((item) => item.type == GameParticipantType.user)
      .map((item) => item.participantId)
      .firstOrNull;

  static List<GameMessage> visibleMessages(GameSession session) {
    final userId = currentUserParticipantId(session);
    return visibleMessagesFor(session, userId);
  }

  static List<GameMessage> visibleMessagesFor(
    GameSession session,
    String? participantId,
  ) => session.messages
      .where((message) {
        if (message.visibility == GameMessageVisibility.public) return true;
        return participantId != null &&
            message.visibleToParticipantId == participantId;
      })
      .toList(growable: false);
}
