import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/games/models/game_models.dart';
import 'package:peijianche_app/games/participation/character_game_action.dart';
import 'package:peijianche_app/games/participation/character_participation_director.dart';
import 'package:peijianche_app/games/participation/game_user_identity.dart';
import 'package:peijianche_app/games/participation/real_character_game_agent.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_character_agent_view_builder.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_character_participation_adapter.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_models.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/models/character_profile.dart';
import 'package:peijianche_app/models/character_settings.dart';

const _allowedActions = {
  CharacterGameActionType.askQuestion,
  CharacterGameActionType.makeGuess,
  CharacterGameActionType.react,
  CharacterGameActionType.pass,
};

void main() {
  const actor = GameParticipant(
    participantId: 'character:c1',
    type: GameParticipantType.character,
    displayName: '阿澈',
    characterId: 'c1',
  );

  GameSession session({
    TurtleSoupPhase phase = TurtleSoupPhase.questioning,
    List<GameMessage> messages = const [],
  }) => GameSession(
    sessionId: 'knowledge-boundary',
    gameId: 'turtle_soup',
    createdAt: DateTime(2026, 9, 20),
    updatedAt: DateTime(2026, 9, 20),
    status: phase == TurtleSoupPhase.finished
        ? GameSessionStatus.finished
        : GameSessionStatus.playing,
    host: const GameHost.system(),
    participants: const [
      GameParticipant(
        participantId: 'user',
        type: GameParticipantType.user,
        displayName: '我',
      ),
      actor,
    ],
    gameState: TurtleSoupState(
      puzzleId: 'p1',
      title: '谜题',
      surface: '公开汤面',
      truth: 'SECRET_SOLUTION_绝不可提前出现',
      hints: const ['未公开提示也不能出现'],
      questionCount: 2,
      guessCount: 1,
      usedHintCount: 0,
      phase: phase,
    ),
    messages: messages,
  );

  const builder = TurtleSoupCharacterAgentViewBuilder();

  AiCharacter character() => AiCharacter(
    id: 'c1',
    characterName: '阿澈',
    remark: '',
    persona: '谨慎但好奇。',
    createdAt: DateTime(2026, 9, 20),
  );

  CharacterGameAgentRequest request({
    Set<CharacterGameActionType> allowedActions = _allowedActions,
  }) => CharacterGameAgentRequest(
    actorParticipantId: actor.participantId,
    characterId: actor.characterId!,
    gameUserIdentity: const GameUserIdentity(
      displayName: '简澈',
      participantId: 'user',
      isLocalUser: true,
    ),
    view: builder.build(
      session: session(),
      actor: actor,
      allowedActions: allowedActions,
    ),
    allowedActions: allowedActions,
  );

  RealCharacterGameAgent agentWithGateway(CharacterGameModelGateway gateway) =>
      RealCharacterGameAgent(
        modelGateway: gateway,
        characterLoader: (_) async => character(),
        settingsLoader: (_) async => CharacterSettings.genericDefaults(),
        profileLoader: (_, _) async =>
            const CharacterProfile(characterId: 'c1'),
      );

  RealCharacterGameAgent agentWithOutput(String output) =>
      agentWithGateway(_RecordingGateway(output));

  test('player knowledge view excludes solution and invisible messages', () {
    final value = session(
      messages: [
        GameMessage(
          id: 'public-question',
          sessionId: 'knowledge-boundary',
          senderId: 'user',
          type: GameMessageType.question,
          content: '公开问题',
        ),
        GameMessage(
          id: 'actor-private',
          sessionId: 'knowledge-boundary',
          senderId: 'host',
          type: GameMessageType.answer,
          content: '角色可见私密回答',
          visibility: GameMessageVisibility.privateToParticipant,
          visibleToParticipantId: 'character:c1',
        ),
        GameMessage(
          id: 'other-private',
          sessionId: 'knowledge-boundary',
          senderId: 'host',
          type: GameMessageType.answer,
          content: '其他人私密答案',
          visibility: GameMessageVisibility.privateToParticipant,
          visibleToParticipantId: 'character:c2',
        ),
      ],
    );
    final view = builder.build(
      session: value,
      actor: actor,
      allowedActions: _allowedActions,
    );
    final prompt = view.toPromptText();
    expect(prompt, contains('公开汤面'));
    expect(prompt, contains('公开问题'));
    expect(prompt, contains('角色可见私密回答'));
    expect(prompt, isNot(contains('其他人私密答案')));
    expect(prompt, isNot(contains('SECRET_SOLUTION')));
    expect(prompt, isNot(contains('未公开提示')));
    expect(view.publicRevealedTruth, isNull);
  });

  test(
    'multiplayer reasoning context is derived from public timeline only',
    () {
      final value = session(
        messages: [
          GameMessage(
            id: 'character-question',
            sessionId: 'knowledge-boundary',
            senderId: 'character:c1',
            type: GameMessageType.question,
            content: '警报是声音触发的吗？',
          ),
          GameMessage(
            id: 'host-answer',
            sessionId: 'knowledge-boundary',
            senderId: 'host',
            type: GameMessageType.answer,
            content: '不是。',
          ),
          GameMessage(
            id: 'partial-question',
            sessionId: 'knowledge-boundary',
            senderId: 'user',
            type: GameMessageType.question,
            content: '和闪光有关吗？',
          ),
          GameMessage(
            id: 'partial-answer',
            sessionId: 'knowledge-boundary',
            senderId: 'host',
            type: GameMessageType.answer,
            content: '方向接近，但还缺条件。',
          ),
          GameMessage(
            id: 'private-direction',
            sessionId: 'knowledge-boundary',
            senderId: 'host',
            type: GameMessageType.answer,
            content: 'SECRET_PRIVATE_DIRECTION',
            visibility: GameMessageVisibility.privateToParticipant,
            visibleToParticipantId: actor.participantId,
          ),
        ],
      );
      final view = builder.build(
        session: value,
        actor: actor,
        allowedActions: _allowedActions,
      );
      final context = view.reasoningContext;
      expect(context.recentRejectedDirections.join(), contains('声音触发'));
      expect(context.recentPartialDirections.join(), contains('闪光'));
      expect(context.recentCharacterQuestions, contains('警报是声音触发的吗？'));
      expect(
        context.toPromptText(),
        isNot(contains('SECRET_PRIVATE_DIRECTION')),
      );
      expect(context.toPromptText(), isNot(contains('SECRET_SOLUTION')));
      expect(context.toPromptText(), isNot(contains('未公开提示')));
    },
  );

  test(
    'empty frontier permits ordinary reactions and imperfect questions',
    () async {
      for (final output in [
        '{"action":"react","content":"（点头）我也想沿着你刚才的思路想想。"}',
        '{"action":"askQuestion","content":"会不会只是忘记了？"}',
      ]) {
        final gateway = _RecordingGateway(output);
        final action = await agentWithGateway(gateway).decide(request());
        expect(action.type, isNot(CharacterGameActionType.pass));
        final prompt = gateway.messages!.map((m) => m['content']).join('\n');
        expect(prompt, contains('不必新增事实'));
        expect(prompt, contains('没有建议也可以正常提问、回应或猜测'));
        expect(prompt, isNot(contains('必须选择 pass')));
        expect(prompt, isNot(contains('SECRET_SOLUTION')));
      }
    },
  );

  test('revealed truth comes only from a visible reveal message', () {
    final revealedWithoutMessage = builder.build(
      session: session(phase: TurtleSoupPhase.revealed),
      actor: actor,
      allowedActions: const {CharacterGameActionType.pass},
    );
    expect(revealedWithoutMessage.publicRevealedTruth, isNull);

    final revealed = builder.build(
      session: session(
        phase: TurtleSoupPhase.revealed,
        messages: [
          GameMessage(
            id: 'public-reveal',
            sessionId: 'knowledge-boundary',
            senderId: 'host',
            type: GameMessageType.reveal,
            content: 'SECRET_SOLUTION_绝不可提前出现',
          ),
        ],
      ),
      actor: actor,
      allowedActions: const {CharacterGameActionType.pass},
    );
    expect(revealed.publicRevealedTruth, contains('SECRET_SOLUTION'));
    expect(
      const TurtleSoupCharacterParticipationAdapter().allowedActions(
        session(phase: TurtleSoupPhase.finished),
        actor,
      ),
      const {CharacterGameActionType.pass},
    );
  });

  test(
    'real agent injects compact personality and parses structured action',
    () async {
      final gateway = _RecordingGateway(
        '{"action":"askQuestion","content":"门当时锁着吗？"}',
      );
      final agent = RealCharacterGameAgent(
        modelGateway: gateway,
        characterLoader: (_) async => character(),
        settingsLoader: (_) async => CharacterSettings.genericDefaults(),
        profileLoader: (_, _) async => const CharacterProfile(
          characterId: 'c1',
          personalityTags: '冷静、敏锐',
          personalityDescription: '习惯先观察细节，再提出关键问题。',
          speakingStyle: '短句，语气克制。',
        ),
      );
      final agentRequest = request();
      final action = await agent.decide(agentRequest);
      expect(action.type, CharacterGameActionType.askQuestion);
      expect(action.content, '门当时锁着吗？');
      final prompt = gateway.messages!
          .map((item) => item['content'])
          .join('\n');
      expect(prompt, contains('阿澈'));
      expect(prompt, contains('冷静、敏锐'));
      expect(prompt, contains('短句，语气克制'));
      expect(prompt, contains('你不知道任何隐藏答案'));
      expect(prompt, contains('简短动作或神态'));
      expect(prompt, contains('react 可以只是合理的游戏内回应'));
      expect(prompt, contains('不必新增事实'));
      expect(prompt, contains('多人协作推理摘要'));
      expect(prompt, contains('公开推理记事板'));
      expect(prompt, contains('结合实际公开问答和提示'));
      expect(prompt, contains('不要反复钻同一细节'));
      expect(prompt, contains('近期部分成立/仍需条件'));
      expect(prompt, contains('只是可选参考，不是行动许可证'));
      expect(prompt, contains('没有建议也可以正常提问、回应或猜测'));
      expect(prompt, contains('不要求优先 Guess'));
      expect(prompt, contains('不必因为没有新的高价值方向就 pass'));
      expect(prompt, contains('同主题换一个角度仍然可以'));
      expect(prompt, contains('允许猜错'));
      expect(prompt, contains('不要仅给旧完整推理链追加小尾巴'));
      expect(prompt, contains('不进入生活闲聊'));
      expect(prompt, contains('公开汤面'));
      expect(prompt, isNot(contains('Archive')));
      expect(gateway.messages, hasLength(2));
    },
  );

  test(
    'malformed, empty and unauthorized structured output safely pass',
    () async {
      for (final output in [
        '不是 JSON',
        '{"action":"unknown","content":"内容"}',
        '{"action":"askQuestion","content":""}',
        '{"action":"makeGuess","content":"越权猜测"}',
      ]) {
        final agent = agentWithOutput(output);
        final action = await agent.decide(
          request(
            allowedActions: const {
              CharacterGameActionType.askQuestion,
              CharacterGameActionType.pass,
            },
          ),
        );
        expect(action.type, CharacterGameActionType.pass, reason: output);
        expect(action.content, isEmpty);
      }
    },
  );

  test('provider error and timeout safely pass', () async {
    final errorAgent = agentWithGateway(_ErrorGateway());
    expect(
      (await errorAgent.decide(request())).type,
      CharacterGameActionType.pass,
    );

    final timeoutAgent = RealCharacterGameAgent(
      modelGateway: _NeverGateway(),
      characterLoader: (_) async => character(),
      settingsLoader: (_) async => CharacterSettings.genericDefaults(),
      profileLoader: (_, _) async => const CharacterProfile(characterId: 'c1'),
      timeout: const Duration(milliseconds: 20),
    );
    expect(
      (await timeoutAgent.decide(request())).type,
      CharacterGameActionType.pass,
    );
  });

  test(
    'deterministic fake stays independent from production model gateway',
    () async {
      const fake = DeterministicCharacterGameAgent(
        actionType: CharacterGameActionType.react,
        content: '测试行动',
      );
      final action = await fake.decide(request());
      expect(action.type, CharacterGameActionType.react);
      expect(action.content, '测试行动');
    },
  );
}

class _RecordingGateway implements CharacterGameModelGateway {
  _RecordingGateway(this.output);
  final String output;
  List<Map<String, dynamic>>? messages;

  @override
  Future<String> complete({
    required List<Map<String, dynamic>> messages,
  }) async {
    this.messages = messages;
    return output;
  }
}

class _ErrorGateway implements CharacterGameModelGateway {
  @override
  Future<String> complete({required List<Map<String, dynamic>> messages}) =>
      Future.error(StateError('provider failed'));
}

class _NeverGateway implements CharacterGameModelGateway {
  @override
  Future<String> complete({required List<Map<String, dynamic>> messages}) =>
      Completer<String>().future;
}
