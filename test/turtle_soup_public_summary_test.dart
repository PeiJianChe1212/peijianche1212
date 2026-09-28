import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/games/models/game_models.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_models.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_public_summary.dart';

void main() {
  GameSession session({List<GameMessage> messages = const []}) => GameSession(
    sessionId: 'summary-room',
    gameId: 'turtle_soup',
    createdAt: DateTime(2026, 9, 22),
    updatedAt: DateTime(2026, 9, 22),
    status: GameSessionStatus.playing,
    host: const GameHost.system(),
    participants: const [
      GameParticipant(
        participantId: 'user',
        type: GameParticipantType.user,
        displayName: '我',
      ),
      GameParticipant(
        participantId: 'character:a',
        type: GameParticipantType.character,
        displayName: '角色A',
        characterId: 'a',
      ),
    ],
    gameState: const TurtleSoupState(
      puzzleId: 'summary',
      title: '无声警报',
      surface: '警报响了，但房间里没有声音。',
      truth: '隐藏真相绝不能进入总结视图',
      hints: ['未公开提示也不能进入视图'],
      phase: TurtleSoupPhase.questioning,
      questionCount: 2,
    ),
    messages: messages,
  );

  GameMessage message(
    String id,
    String sender,
    GameMessageType type,
    String content, {
    GameMessageVisibility visibility = GameMessageVisibility.public,
    String? visibleTo,
  }) => GameMessage(
    id: id,
    sessionId: 'summary-room',
    senderId: sender,
    type: type,
    content: content,
    visibility: visibility,
    visibleToParticipantId: visibleTo,
  );

  test(
    'only surface skips the model and returns insufficient fallback',
    () async {
      final gateway = _RecordingGateway('{}');
      final service = TurtleSoupPublicSummaryService(gateway: gateway);
      final view = const TurtleSoupPublicSummaryViewBuilder().build(session());
      final result = await service.summarize(view);
      expect(gateway.calls, 0);
      expect(result.fallbackMessage, contains('信息还比较少'));
    },
  );

  test('public view contains public timeline and no hidden puzzle fields', () {
    final view = const TurtleSoupPublicSummaryViewBuilder().build(
      session(
        messages: [
          message('q1', 'user', GameMessageType.question, '警报通过声音提醒吗？'),
          message('a1', 'host', GameMessageType.answer, '不是。'),
          message(
            'private',
            'host',
            GameMessageType.answer,
            '私人答案',
            visibility: GameMessageVisibility.privateToParticipant,
            visibleTo: 'other',
          ),
        ],
      ),
    );
    final json = view.toJson();
    expect(json.containsKey('truth'), isFalse);
    expect(json.containsKey('requiredTruthPoints'), isFalse);
    expect(json.containsKey('reasoningDimensions'), isFalse);
    expect(json.toString(), isNot(contains('隐藏真相')));
    expect(json.toString(), isNot(contains('未公开提示')));
    expect(json.toString(), isNot(contains('私人答案')));
    expect(json.toString(), contains('警报通过声音提醒吗'));
  });

  test(
    'structured summary keeps supported items and drops hallucinations',
    () async {
      final gateway = _RecordingGateway('''
{"confirmed":["警报不是依靠声音提醒"],"ruledOut":["特定生物不是关键方向"],"unresolved":["闪光在警报中具体起什么作用","震动装置可能是答案"]}
''');
      final service = TurtleSoupPublicSummaryService(gateway: gateway);
      final view = const TurtleSoupPublicSummaryViewBuilder().build(
        session(
          messages: [
            message('q1', 'user', GameMessageType.question, '警报通过声音提醒吗？'),
            message('a1', 'host', GameMessageType.answer, '不是。'),
            message('q2', 'character:a', GameMessageType.question, '警报与闪光有关吗？'),
            message('a2', 'host', GameMessageType.answer, '方向接近，但还缺少关键条件。'),
            message(
              'q3',
              'character:a',
              GameMessageType.question,
              '警报和特定生物有关吗？',
            ),
            message('a3', 'host', GameMessageType.answer, '这个方向与关键点关系不大。'),
          ],
        ),
      );
      final result = await service.summarize(view);
      expect(result.confirmed, contains('警报不是依靠声音提醒'));
      expect(result.ruledOut, contains('特定生物不是关键方向'));
      expect(result.unresolved, contains('闪光在警报中具体起什么作用'));
      expect(result.unresolved, isNot(contains('震动装置可能是答案')));
      expect(gateway.lastPrompt, isNot(contains('隐藏真相')));
    },
  );

  test('malformed, provider error and timeout safely fallback', () async {
    final view = const TurtleSoupPublicSummaryViewBuilder().build(
      session(
        messages: [
          message('q1', 'user', GameMessageType.question, '声音有关吗？'),
          message('q2', 'character:a', GameMessageType.question, '闪光有关吗？'),
        ],
      ),
    );
    final malformed = await TurtleSoupPublicSummaryService(
      gateway: _RecordingGateway('not-json'),
    ).summarize(view);
    expect(malformed.fallbackMessage, isNotNull);
    final failed = await TurtleSoupPublicSummaryService(
      gateway: _ErrorGateway(),
    ).summarize(view);
    expect(failed.fallbackMessage, isNotNull);
    final timedOut = await TurtleSoupPublicSummaryService(
      gateway: _NeverGateway(),
      timeout: const Duration(milliseconds: 10),
    ).summarize(view);
    expect(timedOut.fallbackMessage, isNotNull);
  });
}

class _RecordingGateway implements TurtleSoupSummaryModelGateway {
  _RecordingGateway(this.output);
  final String output;
  int calls = 0;
  String lastPrompt = '';

  @override
  Future<String> complete({
    required List<Map<String, dynamic>> messages,
  }) async {
    calls++;
    lastPrompt = messages.last['content']?.toString() ?? '';
    return output;
  }
}

class _ErrorGateway implements TurtleSoupSummaryModelGateway {
  @override
  Future<String> complete({required List<Map<String, dynamic>> messages}) =>
      Future.error(StateError('provider failed'));
}

class _NeverGateway implements TurtleSoupSummaryModelGateway {
  @override
  Future<String> complete({required List<Map<String, dynamic>> messages}) =>
      Completer<String>().future;
}
