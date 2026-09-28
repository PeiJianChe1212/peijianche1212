import '../../models/ai_character.dart';
import '../models/game_models.dart';

class GameTimelineSenderResolver {
  GameTimelineSenderResolver({
    required this.session,
    Iterable<AiCharacter> characters = const [],
  }) : _characterNames = {
         for (final character in characters)
           character.id: character.displayName.trim(),
       };

  final GameSession session;
  final Map<String, String> _characterNames;

  String labelFor(GameMessage message) {
    if (_isSystemMessage(message)) return '系统';
    if (_isHostMessage(message)) return _hostLabel(message);
    final participant = session.participants
        .where((item) => item.participantId == message.senderId)
        .firstOrNull;
    final sender = switch (participant?.type) {
      GameParticipantType.user => '我',
      GameParticipantType.character => _characterName(participant!),
      _ => '系统',
    };
    return '$sender · ${typeLabel(message.type)}';
  }

  String _hostLabel(GameMessage message) {
    if (session.host.type == GameHostType.systemHost) {
      return '主持 · ${typeLabel(message.type)}';
    }
    final characterId = session.host.characterId;
    final participant = session.participants
        .where((item) => item.characterId == characterId)
        .firstOrNull;
    final registryName = _characterNames[characterId]?.trim() ?? '';
    final snapshotName = participant?.displayName.trim() ?? '';
    final name = registryName.isNotEmpty
        ? registryName
        : snapshotName.isNotEmpty
        ? snapshotName
        : '角色主持人';
    return '$name · 主持';
  }

  String _characterName(GameParticipant participant) {
    final registryName = _characterNames[participant.characterId]?.trim() ?? '';
    if (registryName.isNotEmpty) return registryName;
    final snapshotName = participant.displayName.trim();
    return snapshotName.isNotEmpty ? snapshotName : '角色';
  }

  bool _isHostMessage(GameMessage message) =>
      message.senderId == 'host' || message.type == GameMessageType.host;

  bool _isSystemMessage(GameMessage message) =>
      message.senderId == 'system' ||
      {
        GameMessageType.system,
        GameMessageType.narration,
      }.contains(message.type);

  static String typeLabel(GameMessageType type) => switch (type) {
    GameMessageType.question => '提问',
    GameMessageType.answer || GameMessageType.host => '回答',
    GameMessageType.guess => '猜测',
    GameMessageType.hint => '提示',
    GameMessageType.participant => '回应',
    GameMessageType.reveal => '真相',
    GameMessageType.puzzle => '谜面',
    _ => '系统',
  };
}
