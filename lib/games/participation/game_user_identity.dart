import '../models/game_models.dart';

class GameUserIdentity {
  const GameUserIdentity({
    required this.displayName,
    required this.participantId,
    required this.isLocalUser,
  });

  final String displayName;
  final String participantId;
  final bool isLocalUser;

  factory GameUserIdentity.fromSession(GameSession session) {
    final participant = session.participants
        .where((item) => item.type == GameParticipantType.user)
        .firstOrNull;
    final rawName = participant?.displayName.trim() ?? '';
    final displayName = rawName.isEmpty || rawName == '未设置' ? '我' : rawName;
    return GameUserIdentity(
      displayName: displayName,
      participantId: participant?.participantId ?? 'user',
      isLocalUser: true,
    );
  }
}
