import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/games/models/game_models.dart';
import 'package:peijianche_app/games/participation/character_game_action.dart';
import 'package:peijianche_app/games/participation/character_game_agent_view.dart';
import 'package:peijianche_app/games/participation/character_participation_director.dart';
import 'package:peijianche_app/games/participation/game_user_identity.dart';
import 'package:peijianche_app/games/participation/real_character_game_agent.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/models/character_profile.dart';
import 'package:peijianche_app/models/character_settings.dart';

void main() {
  GameSession session({String displayName = '简澈'}) => GameSession(
    sessionId: 'game-user-boundary',
    gameId: 'turtle_soup',
    createdAt: DateTime(2026, 9, 20),
    updatedAt: DateTime(2026, 9, 20),
    status: GameSessionStatus.playing,
    host: const GameHost.system(),
    participants: [
      GameParticipant(
        participantId: 'user',
        type: GameParticipantType.user,
        displayName: displayName,
        userIdentityReference: 'PRIVATE_PEI_LINK_ID',
      ),
      const GameParticipant(
        participantId: 'character:c1',
        type: GameParticipantType.character,
        displayName: '阿澈',
        characterId: 'c1',
      ),
    ],
    gameState: const _TestState(),
  );

  test('game user identity uses only the local participant snapshot', () {
    final identity = GameUserIdentity.fromSession(session());
    expect(identity.displayName, '简澈');
    expect(identity.participantId, 'user');
    expect(identity.isLocalUser, isTrue);

    expect(
      GameUserIdentity.fromSession(session(displayName: '')).displayName,
      '我',
    );
    expect(
      GameUserIdentity.fromSession(session(displayName: '未设置')).displayName,
      '我',
    );
  });

  test(
    'game agent keeps character voice but excludes unsafe world context',
    () async {
      final gateway = _RecordingGateway();
      final character = AiCharacter(
        id: 'c1',
        characterName: '阿澈',
        remark: '',
        persona: 'DANGEROUS_PERSONA：用户是恋人兼上司。',
        characterIntro: 'DANGEROUS_INTRO：用户来自魔法学院。',
        relationship: 'DANGEROUS_RELATIONSHIP',
        introduction: 'DANGEROUS_CARD_USER_STORY',
        createdAt: DateTime(2026, 9, 20),
      );
      final agent = RealCharacterGameAgent(
        modelGateway: gateway,
        characterLoader: (_) async => character,
        settingsLoader: (_) async => CharacterSettings.genericDefaults(),
        profileLoader: (_, _) async => const CharacterProfile(
          characterId: 'c1',
          personalityTags: '冷静、敏锐',
          personalityDescription: 'DANGEROUS_LEGACY_CORE_PROFILE',
          speakingStyle: '短句，克制，偶尔带简短动作。',
          relationship: 'DANGEROUS_PROFILE_RELATIONSHIP',
          howMet: 'DANGEROUS_HOW_MET',
          backgroundStory: 'DANGEROUS_ARCHIVE_STORY',
        ),
      );
      await agent.decide(
        CharacterGameAgentRequest(
          actorParticipantId: 'character:c1',
          characterId: 'c1',
          gameUserIdentity: GameUserIdentity.fromSession(session()),
          view: const CharacterGameAgentView(
            gameId: 'turtle_soup',
            publicPhase: 'questioning',
            publicSurface: '公开谜面',
            visibleHistory: [],
            publicStats: {'questions': 0},
            allowedActions: {
              CharacterGameActionType.askQuestion,
              CharacterGameActionType.pass,
            },
          ),
          allowedActions: const {
            CharacterGameActionType.askQuestion,
            CharacterGameActionType.pass,
          },
        ),
      );
      final prompt = gateway.messages
          .map((message) => message['content']?.toString() ?? '')
          .join('\n');
      expect(prompt, contains('当前本地用户玩家名为“简澈”'));
      expect(prompt, contains('共同参与本局游戏的玩家'));
      expect(prompt, contains('冷静、敏锐'));
      expect(prompt, contains('短句，克制'));
      expect(prompt, contains('避免仅换措辞重复同一个问题'));
      expect(prompt, contains('想安静听一会儿时可以 pass'));
      expect(prompt, contains('公开谜面'));
      for (final forbidden in [
        'DANGEROUS_PERSONA',
        'DANGEROUS_INTRO',
        'DANGEROUS_RELATIONSHIP',
        'DANGEROUS_CARD_USER_STORY',
        'DANGEROUS_LEGACY_CORE_PROFILE',
        'DANGEROUS_PROFILE_RELATIONSHIP',
        'DANGEROUS_HOW_MET',
        'DANGEROUS_ARCHIVE_STORY',
        'PRIVATE_PEI_LINK_ID',
        'Memory',
        'Echo',
      ]) {
        expect(prompt, isNot(contains(forbidden)), reason: forbidden);
      }
    },
  );
}

class _RecordingGateway implements CharacterGameModelGateway {
  List<Map<String, dynamic>> messages = const [];

  @override
  Future<String> complete({
    required List<Map<String, dynamic>> messages,
  }) async {
    this.messages = messages;
    return '{"action":"pass","content":""}';
  }
}

class _TestState extends GameStateSnapshot {
  const _TestState();

  @override
  String get stateType => 'test';

  @override
  Map<String, dynamic> toJson() => const {'stateType': 'test'};
}
