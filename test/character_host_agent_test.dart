import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/games/hosting/character_host_agent.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/models/character_profile.dart';

void main() {
  test('host identity whitelist keeps voice and excludes world context', () {
    final character = AiCharacter(
      id: 'c1',
      characterName: '老裴',
      remark: '',
      persona: 'UNSAFE_WORLDVIEW',
      characterIntro: 'UNSAFE_USER_STORY',
      relationship: 'UNSAFE_RELATIONSHIP',
      introduction: 'UNSAFE_INTRO',
      createdAt: DateTime(2026, 9, 20),
    );
    const profile = CharacterProfile(
      characterId: 'c1',
      personalityTags: '沉稳、敏锐',
      speakingStyle: '短句，克制。',
      personalityDescription: 'UNSAFE_DESCRIPTION',
      relationship: 'UNSAFE_PROFILE_RELATIONSHIP',
      backgroundStory: 'UNSAFE_ARCHIVE',
      worldview: 'UNSAFE_PROFILE_WORLDVIEW',
    );

    final identity = SafeCharacterHostIdentityLoader.identityFrom(
      character,
      profile,
    );
    expect(identity.displayName, '老裴');
    expect(identity.personalityTags, '沉稳、敏锐');
    expect(identity.speakingStyle, '短句，克制。');
    expect(identity.toString(), isNot(contains('UNSAFE')));
  });
}
