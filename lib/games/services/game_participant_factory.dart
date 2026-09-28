import '../../models/ai_character.dart';
import '../../models/user_profile.dart';
import '../models/game_models.dart';

abstract final class GameParticipantFactory {
  static GameParticipant user(UserProfile profile) => GameParticipant(
    participantId: 'user',
    type: GameParticipantType.user,
    displayName: profile.nickname.trim().isEmpty ? '我' : profile.nickname,
    avatarReference: profile.avatarPath,
    userIdentityReference: profile.peiLinkId,
  );

  static GameParticipant character(AiCharacter character) => GameParticipant(
    participantId: 'character:${character.id}',
    type: GameParticipantType.character,
    displayName: character.displayName,
    avatarReference: character.effectiveSocialAvatarPath,
    characterId: character.id,
  );
}
