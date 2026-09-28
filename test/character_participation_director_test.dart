import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/games/models/game_models.dart';
import 'package:peijianche_app/games/participation/character_game_action.dart';
import 'package:peijianche_app/games/participation/character_participation_director.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_character_participation_adapter.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_character_agent_view_builder.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_engine.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_models.dart';

void main() {
  const legality = TurtleSoupCharacterParticipationAdapter();
  const viewBuilder = TurtleSoupCharacterAgentViewBuilder();

  GameParticipant character(String id) => GameParticipant(
    participantId: 'character:$id',
    type: GameParticipantType.character,
    displayName: id,
    characterId: id,
  );

  GameSession session({
    GameSessionStatus status = GameSessionStatus.playing,
    GameHost host = const GameHost.system(),
    List<GameParticipant>? participants,
    TurtleSoupPhase phase = TurtleSoupPhase.questioning,
    List<GameMessage> messages = const [],
  }) => GameSession(
    sessionId: 'participation-test',
    gameId: 'turtle_soup',
    createdAt: DateTime(2026, 9, 20),
    updatedAt: DateTime(2026, 9, 20),
    status: status,
    host: host,
    participants:
        participants ??
        [
          const GameParticipant(
            participantId: 'user',
            type: GameParticipantType.user,
            displayName: '我',
          ),
          character('a'),
          character('b'),
        ],
    gameState: TurtleSoupState(
      puzzleId: 'late_delivery',
      title: '测试',
      surface: '谜面',
      truth: '真相',
      hints: const ['提示'],
      phase: phase,
    ),
    messages: messages,
  );

  const trigger = GameAction(
    type: GameActionType.custom,
    actorParticipantId: 'user',
    payload: {'kind': 'question', 'text': '用户问题'},
  );

  Future<CharacterParticipationDecision> decideAgainstHistory({
    required CharacterGameActionType type,
    required String content,
    required List<GameMessage> messages,
  }) async {
    final director = CharacterParticipationDirector(
      agent: DeterministicCharacterGameAgent(
        actionType: type,
        content: content,
      ),
      legality: legality,
      viewBuilder: viewBuilder,
    );
    final value = session(messages: messages);
    return director.offerTurn(
      session: value,
      trigger: trigger,
      round: director.startRound(value),
    );
  }

  GameSession applyEvents(
    GameSession value,
    GameResult<List<GameEvent>> result,
  ) {
    var state = value.gameState;
    var status = value.status;
    final messages = [...value.messages];
    for (final event in result.value ?? const <GameEvent>[]) {
      if (event.state != null) state = event.state!;
      if (event.message != null) messages.add(event.message!);
      if (event.type == GameEventType.gameFinished) {
        status = GameSessionStatus.finished;
      }
    }
    return value.copyWith(gameState: state, status: status, messages: messages);
  }

  test(
    'four-character round gives each character at most one ordered turn',
    () async {
      final recording = _RecordingAgent();
      final director = CharacterParticipationDirector(
        agent: recording,
        legality: legality,
        viewBuilder: viewBuilder,
      );
      final value = session(
        participants: [
          const GameParticipant(
            participantId: 'user',
            type: GameParticipantType.user,
            displayName: '我',
          ),
          character('a'),
          character('b'),
          character('c'),
          character('d'),
        ],
      );
      var round = director.startRound(value);
      while (!round.isComplete) {
        await director.offerTurn(
          session: value,
          trigger: trigger,
          round: round,
        );
        round = round.advance();
      }
      expect(recording.participantIds, [
        'character:a',
        'character:b',
        'character:c',
        'character:d',
      ]);
    },
  );

  test('director injects neutral game user identity into the turn', () async {
    final recording = _RecordingAgent();
    final director = CharacterParticipationDirector(
      agent: recording,
      legality: legality,
      viewBuilder: viewBuilder,
    );
    final value = session(
      participants: [
        const GameParticipant(
          participantId: 'local-player',
          type: GameParticipantType.user,
          displayName: '小简',
          userIdentityReference: 'private-profile-reference',
        ),
        character('a'),
      ],
    );
    await director.offerTurn(
      session: value,
      trigger: trigger,
      round: director.startRound(value),
    );
    expect(recording.lastUserDisplayName, '小简');
    expect(recording.lastUserParticipantId, 'local-player');
  });

  test('pass and agent failure advance to the remaining characters', () async {
    final visited = <String>[];
    final director = CharacterParticipationDirector(
      agent: _ScriptedAgent((request) async {
        visited.add(request.actorParticipantId);
        if (request.actorParticipantId == 'character:a') {
          return CharacterGameAction(
            actorParticipantId: request.actorParticipantId,
            type: CharacterGameActionType.pass,
          );
        }
        if (request.actorParticipantId == 'character:b') {
          throw StateError('provider failed');
        }
        return CharacterGameAction(
          actorParticipantId: request.actorParticipantId,
          type: CharacterGameActionType.react,
          content: '继续推理',
        );
      }),
      legality: legality,
      viewBuilder: viewBuilder,
    );
    final value = session(
      participants: [
        const GameParticipant(
          participantId: 'user',
          type: GameParticipantType.user,
          displayName: '我',
        ),
        character('a'),
        character('b'),
        character('c'),
      ],
    );
    var round = director.startRound(value);
    final decisions = <CharacterParticipationDecision>[];
    while (!round.isComplete) {
      decisions.add(
        await director.offerTurn(
          session: value,
          trigger: trigger,
          round: round,
        ),
      );
      round = round.advance();
    }
    expect(visited, ['character:a', 'character:b', 'character:c']);
    expect(decisions.map((item) => item.reason), [
      'pass',
      'agent-failed',
      'action',
    ]);
  });

  test('each turn rebuilds knowledge from the latest engine session', () async {
    final views = <CharacterGameAgentRequest>[];
    final director = CharacterParticipationDirector(
      agent: _ScriptedAgent((request) async {
        views.add(request);
        return CharacterGameAction(
          actorParticipantId: request.actorParticipantId,
          type: CharacterGameActionType.askQuestion,
          content: request.actorParticipantId == 'character:a'
              ? '这是第一个角色的问题吗？'
              : '这是承接后的问题吗？',
        );
      }),
      legality: legality,
      viewBuilder: viewBuilder,
    );
    var value = session();
    var round = director.startRound(value);
    final first = await director.offerTurn(
      session: value,
      trigger: trigger,
      round: round,
    );
    value = applyEvents(
      value,
      await const TurtleSoupEngine().handleCharacterAction(
        value,
        first.action!.toEngineAction(),
      ),
    );
    round = round.advance();
    await director.offerTurn(session: value, trigger: trigger, round: round);
    expect(views, hasLength(2));
    final secondView = views.last.view;
    expect(
      secondView.visibleHistory.map((item) => item.content),
      contains('这是第一个角色的问题吗？'),
    );
    expect(
      secondView.visibleHistory.any(
        (item) => item.type == GameMessageType.answer,
      ),
      isTrue,
    );
    expect(secondView.publicRevealedTruth, isNull);
  });

  test('the same round turn cannot be claimed twice', () async {
    final director = CharacterParticipationDirector(
      agent: _RecordingAgent(),
      legality: legality,
      viewBuilder: viewBuilder,
    );
    final value = session();
    final round = director.startRound(value);
    expect(
      (await director.offerTurn(
        session: value,
        trigger: trigger,
        round: round,
      )).hasAction,
      isTrue,
    );
    final duplicate = await director.offerTurn(
      session: value,
      trigger: trigger,
      round: round,
    );
    expect(duplicate.hasAction, isFalse);
    expect(duplicate.reason, 'turn-already-claimed');
  });

  test(
    'roster changes skip invalid turns without cancelling the round',
    () async {
      final recording = _RecordingAgent();
      final director = CharacterParticipationDirector(
        agent: recording,
        legality: legality,
        viewBuilder: viewBuilder,
      );
      final original = session();
      var round = director.startRound(original);
      final withoutFirstCharacter = session(
        participants: [
          const GameParticipant(
            participantId: 'user',
            type: GameParticipantType.user,
            displayName: '我',
          ),
          character('b'),
        ],
      );
      final skipped = await director.offerTurn(
        session: withoutFirstCharacter,
        trigger: trigger,
        round: round,
      );
      expect(skipped.reason, 'candidate-unavailable');
      round = round.advance();
      final next = await director.offerTurn(
        session: withoutFirstCharacter,
        trigger: trigger,
        round: round,
      );
      expect(next.hasAction, isTrue);
      expect(recording.lastParticipantId, 'character:b');
    },
  );

  test(
    'valid user opportunity produces at most one character engine action',
    () async {
      final director = CharacterParticipationDirector(
        agent: const DeterministicCharacterGameAgent(
          actionType: CharacterGameActionType.react,
          content: '我觉得可以换个方向。',
        ),
        legality: legality,
        viewBuilder: viewBuilder,
        minimumInterval: Duration.zero,
      );
      final decision = await director.offerOpportunity(
        session: session(),
        trigger: trigger,
      );
      expect(decision.action?.actorParticipantId, 'character:a');
      final result = await const TurtleSoupEngine().handleCharacterAction(
        session(),
        decision.action!.toEngineAction(),
      );
      expect(result.isSuccess, isTrue);
      final messages = result.value!
          .map((event) => event.message)
          .whereType<GameMessage>()
          .toList();
      expect(messages, hasLength(1));
      expect(messages.single.senderId, 'character:a');
      expect(messages.single.type, GameMessageType.participant);
    },
  );

  test('director can pass without producing an engine action', () async {
    final director = CharacterParticipationDirector(
      agent: const DeterministicCharacterGameAgent(
        actionType: CharacterGameActionType.pass,
      ),
      legality: legality,
      viewBuilder: viewBuilder,
      minimumInterval: Duration.zero,
    );
    final decision = await director.offerOpportunity(
      session: session(),
      trigger: trigger,
    );
    expect(decision.hasAction, isFalse);
    expect(decision.reason, 'pass');
  });

  test('host-only character is excluded from player candidates', () async {
    final recording = _RecordingAgent();
    final director = CharacterParticipationDirector(
      agent: recording,
      legality: legality,
      viewBuilder: viewBuilder,
      minimumInterval: Duration.zero,
    );
    await director.offerOpportunity(
      session: session(
        host: const GameHost.character('host-only'),
        participants: [
          const GameParticipant(
            participantId: 'user',
            type: GameParticipantType.user,
            displayName: '我',
          ),
          character('player'),
        ],
      ),
      trigger: trigger,
    );
    expect(recording.lastParticipantId, 'character:player');
  });

  test('character host remains eligible when also a participant', () async {
    final recording = _RecordingAgent();
    final director = CharacterParticipationDirector(
      agent: recording,
      legality: legality,
      viewBuilder: viewBuilder,
      minimumInterval: Duration.zero,
    );
    final value = session(
      host: const GameHost.character('host-player'),
      participants: [
        const GameParticipant(
          participantId: 'user',
          type: GameParticipantType.user,
          displayName: '我',
        ),
        character('host-player'),
      ],
    );
    final decision = await director.offerOpportunity(
      session: value,
      trigger: trigger,
    );
    expect(recording.lastParticipantId, 'character:host-player');
    expect(decision.hasAction, isTrue);
  });

  test('unavailable character participant is excluded', () async {
    final recording = _RecordingAgent();
    final director = CharacterParticipationDirector(
      agent: recording,
      legality: legality,
      viewBuilder: viewBuilder,
      minimumInterval: Duration.zero,
      participantIsAvailable: (participant) =>
          participant.characterId != 'removed',
    );
    final value = session(
      participants: [
        const GameParticipant(
          participantId: 'user',
          type: GameParticipantType.user,
          displayName: '我',
        ),
        character('removed'),
        character('active'),
      ],
    );
    await director.offerOpportunity(session: value, trigger: trigger);
    expect(recording.lastParticipantId, 'character:active');
  });

  test('non-playing and revealed sessions reject character gameplay', () async {
    final director = CharacterParticipationDirector(
      agent: const DeterministicCharacterGameAgent(
        actionType: CharacterGameActionType.react,
        content: '不会出现',
      ),
      legality: legality,
      viewBuilder: viewBuilder,
      minimumInterval: Duration.zero,
    );
    final readyDecision = await director.offerOpportunity(
      session: session(status: GameSessionStatus.ready),
      trigger: trigger,
    );
    expect(readyDecision.hasAction, isFalse);

    final revealed = session(phase: TurtleSoupPhase.revealed);
    final revealedDecision = await director.offerOpportunity(
      session: revealed,
      trigger: trigger,
    );
    expect(revealedDecision.hasAction, isFalse);
    final rejected = await const TurtleSoupEngine().handleCharacterAction(
      revealed,
      const CharacterGameAction(
        actorParticipantId: 'character:a',
        type: CharacterGameActionType.react,
        content: '非法行动',
      ).toEngineAction(),
    );
    expect(rejected.code, GameResultCode.invalidState);
    expect(rejected.value, isNull);
  });

  test('busy director permits no concurrent character fan-out', () async {
    final completer = Completer<CharacterGameAction>();
    final director = CharacterParticipationDirector(
      agent: _BlockingAgent(completer.future),
      legality: legality,
      viewBuilder: viewBuilder,
      minimumInterval: Duration.zero,
    );
    final first = director.offerOpportunity(
      session: session(),
      trigger: trigger,
    );
    await Future<void>.delayed(Duration.zero);
    final concurrent = await director.offerOpportunity(
      session: session(),
      trigger: trigger,
    );
    expect(concurrent.hasAction, isFalse);
    expect(concurrent.reason, 'director-busy');
    completer.complete(
      const CharacterGameAction(
        actorParticipantId: 'character:a',
        type: CharacterGameActionType.react,
        content: '一次行动',
      ),
    );
    expect((await first).hasAction, isTrue);
  });

  test('near-verbatim same-kind round action becomes a silent pass', () async {
    const firstGuess = '植物园闭园后温室每晚亮灯，是为了给需要特定时长光照才能开花的特定植物补光，所以值班员说里面没人也不是忘关灯';
    const repeatedGuess =
        '植物园闭园后温室每晚亮灯，是为了给需要特定时长光照才能开花的热带幼苗补光，所以值班员说里面没人也不是忘关灯';
    final director = CharacterParticipationDirector(
      agent: const DeterministicCharacterGameAgent(
        actionType: CharacterGameActionType.makeGuess,
        content: repeatedGuess,
      ),
      legality: legality,
      viewBuilder: viewBuilder,
    );
    final value = session(
      messages: [
        GameMessage(
          sessionId: 'participation-test',
          senderId: 'character:a',
          type: GameMessageType.guess,
          content: firstGuess,
        ),
      ],
    );
    final decision = await director.offerTurn(
      session: value,
      trigger: trigger,
      round: director.startRound(value),
    );
    expect(decision.hasAction, isFalse);
    expect(decision.reason, 'semantic-duplicate');
  });

  test('same direction with a new key fact remains a valid action', () async {
    final director = CharacterParticipationDirector(
      agent: const DeterministicCharacterGameAgent(
        actionType: CharacterGameActionType.askQuestion,
        content: '补光的时长是不是恰好对应那株花的昼夜周期，而且只在冬季发生？',
      ),
      legality: legality,
      viewBuilder: viewBuilder,
    );
    final value = session(
      messages: [
        GameMessage(
          sessionId: 'participation-test',
          senderId: 'user',
          type: GameMessageType.question,
          content: '亮灯是不是为了给植物补光？',
        ),
      ],
    );
    final decision = await director.offerTurn(
      session: value,
      trigger: trigger,
      round: director.startRound(value),
    );
    expect(decision.hasAction, isTrue);
  });

  test('full old guess plus a small tail is suppressed', () async {
    const oldGuess = '换气系统故障导致楼内持续负压，密封午餐盒的柔性密封盖向内凹陷，研究员发现这个异常并确认楼内出了问题。';
    final decision = await decideAgainstHistory(
      type: CharacterGameActionType.makeGuess,
      content: '$oldGuess而且这发生在午休结束之前。',
      messages: [
        GameMessage(
          sessionId: 'participation-test',
          senderId: 'character:q',
          type: GameMessageType.guess,
          content: oldGuess,
        ),
      ],
    );
    expect(decision.hasAction, isFalse);
    expect(decision.reason, 'semantic-duplicate');
  });

  test('paraphrased endpoints do not hide a repeated guess chain', () async {
    final decision = await decideAgainstHistory(
      type: CharacterGameActionType.makeGuess,
      content:
          '换气系统故障导致楼内持续负压，密封午餐盒的柔性密封盖向内凹陷，研究员发现这个异常，结合传感器没正常工作的情况，及时知道楼出了问题。',
      messages: [
        GameMessage(
          sessionId: 'participation-test',
          senderId: 'character:q',
          type: GameMessageType.guess,
          content: '通风设备坏了导致楼内持续负压，密封午餐盒的柔性密封盖向内凹陷，研究员发现这个异常就及时知道楼出了问题。',
        ),
      ],
    );
    expect(decision.hasAction, isFalse);
    expect(decision.reason, 'semantic-duplicate');
  });

  test(
    'same topic question with a concrete new condition is allowed',
    () async {
      final decision = await decideAgainstHistory(
        type: CharacterGameActionType.askQuestion,
        content: '传感器是不是因为一直没有维护才没正常工作？',
        messages: [
          GameMessage(
            sessionId: 'participation-test',
            senderId: 'character:w',
            type: GameMessageType.question,
            content: '传感器是不是没有正常工作？',
          ),
          GameMessage(
            sessionId: 'participation-test',
            senderId: 'host',
            type: GameMessageType.answer,
            content: '是的。',
          ),
        ],
      );
      expect(decision.hasAction, isTrue);
    },
  );

  test('question that refines a new host answer is allowed', () async {
    final decision = await decideAgainstHistory(
      type: CharacterGameActionType.askQuestion,
      content: '既然没有报警，是不是因为传感器的维护周期已经过期？',
      messages: [
        GameMessage(
          sessionId: 'participation-test',
          senderId: 'character:w',
          type: GameMessageType.question,
          content: '传感器是不是没有正常工作？',
        ),
        GameMessage(
          sessionId: 'participation-test',
          senderId: 'host',
          type: GameMessageType.answer,
          content: '是，因为它没有报警。',
        ),
      ],
    );
    expect(decision.hasAction, isTrue);
  });

  test('a completely new guess direction is allowed', () async {
    final decision = await decideAgainstHistory(
      type: CharacterGameActionType.makeGuess,
      content: '午餐盒可能被人提前放进冷冻柜，温差让盒内空气收缩，所以盖子才向内凹陷。',
      messages: [
        GameMessage(
          sessionId: 'participation-test',
          senderId: 'character:q',
          type: GameMessageType.guess,
          content: '换气系统故障导致楼内持续负压，密封午餐盒的柔性密封盖向内凹陷，研究员由此发现异常。',
        ),
      ],
    );
    expect(decision.hasAction, isTrue);
  });
}

class _RecordingAgent implements CharacterGameAgent {
  String? lastParticipantId;
  String? lastUserDisplayName;
  String? lastUserParticipantId;
  final List<String> participantIds = [];

  @override
  Future<CharacterGameAction> decide(CharacterGameAgentRequest request) async {
    lastParticipantId = request.actorParticipantId;
    lastUserDisplayName = request.gameUserIdentity.displayName;
    lastUserParticipantId = request.gameUserIdentity.participantId;
    participantIds.add(request.actorParticipantId);
    return CharacterGameAction(
      actorParticipantId: request.actorParticipantId,
      type: CharacterGameActionType.react,
      content: '记录行动',
    );
  }
}

class _ScriptedAgent implements CharacterGameAgent {
  const _ScriptedAgent(this.handler);
  final Future<CharacterGameAction> Function(CharacterGameAgentRequest request)
  handler;

  @override
  Future<CharacterGameAction> decide(CharacterGameAgentRequest request) =>
      handler(request);
}

class _BlockingAgent implements CharacterGameAgent {
  const _BlockingAgent(this.future);
  final Future<CharacterGameAction> future;

  @override
  Future<CharacterGameAction> decide(CharacterGameAgentRequest request) =>
      future;
}
