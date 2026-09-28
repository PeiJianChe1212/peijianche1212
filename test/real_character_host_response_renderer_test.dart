import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/games/hosting/character_host_agent.dart';
import 'package:peijianche_app/games/hosting/real_character_host_response_renderer.dart';
import 'package:peijianche_app/games/participation/game_user_identity.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_semantic_judge.dart';

void main() {
  test('production factory selects the real Character Host renderer', () {
    expect(
      createProductionCharacterHostRenderer(),
      isA<RealCharacterHostResponseRenderer>(),
    );
  });

  CharacterHostRenderRequest request(
    GameHostSemanticType type,
    String canonical, {
    bool reveal = false,
  }) => CharacterHostRenderRequest(
    sessionId: 's1',
    responseMessageId: 'host-message-1',
    characterId: 'c1',
    identity: const CharacterHostIdentity(displayName: 'fallback'),
    gameUserIdentity: const GameUserIdentity(
      displayName: '简澈',
      participantId: 'user:1',
      isLocalUser: true,
    ),
    view: CharacterHostKnowledgeView(
      gameId: 'turtle_soup',
      phase: reveal ? 'finished' : 'questioning',
      publicPuzzle: '公开谜面',
      hiddenTruth: '真相是志愿者协助管理员确认阅览室无人。',
      protectedFacts: const ['志愿者', '协助管理员', '确认无人'],
      publicHistory: const [],
      triggerActorId: 'user:1',
      triggerKind: 'question',
      triggerContent: '和工作有关吗？',
      semanticResult: GameHostSemanticResult(
        type: type,
        canonicalText: canonical,
      ),
      truthMayBeRevealed: reveal,
    ),
  );

  RealCharacterHostResponseRenderer renderer(
    String response, {
    bool fail = false,
    Duration timeout = const Duration(seconds: 1),
  }) => RealCharacterHostResponseRenderer(
    modelGateway: _FakeModelGateway(response, fail: fail),
    identityLoader: (_) async => const CharacterHostIdentity(
      displayName: '老裴',
      personalityTags: '沉稳、敏锐',
      speakingStyle: '短句，克制。',
    ),
    timeout: timeout,
  );

  test(
    'deferred renderer returns canonical text without waiting for model',
    () async {
      final completer = Completer<String>();
      final callback = Completer<(String, int)>();
      final target = request(GameHostSemanticType.answerYes, '是的。');
      final deferred = DeferredCharacterHostResponseRenderer(
        delegate: _CompletingRenderer(completer.future),
        epochProvider: () => 7,
        onRendered: (request, text, epoch) async {
          callback.complete((text, epoch));
        },
      );
      expect(await deferred.render(target), '是的。');
      expect(callback.isCompleted, isFalse);
      completer.complete('（点头）是，这个方向对。');
      expect(await callback.future, ('（点头）是，这个方向对。', 7));
    },
  );

  test('real renderer uses safe identity and structured JSON', () async {
    final gateway = _FakeModelGateway(jsonEncode({'text': '（点头）是，这个方向对。'}));
    final value = await RealCharacterHostResponseRenderer(
      modelGateway: gateway,
      identityLoader: (_) async => const CharacterHostIdentity(
        displayName: '老裴',
        personalityTags: '沉稳、敏锐',
        speakingStyle: '短句，克制。',
      ),
    ).render(request(GameHostSemanticType.answerYes, '是的。'));
    expect(value, contains('是'));
    final prompt = gateway.messages
        .map((item) => item['content'].toString())
        .join('\n');
    expect(prompt, contains('老裴'));
    expect(prompt, contains('沉稳、敏锐'));
    expect(prompt, contains('简澈'));
    expect(prompt, contains('authoritativeSemantic: answerYes'));
    expect(prompt, isNot(contains('relationship')));
    expect(prompt, isNot(contains('protectedTruth')));
    expect(prompt, isNot(contains('真相是志愿者协助管理员确认阅览室无人')));
    expect(prompt, isNot(contains('确认无人')));
  });

  test(
    'partial host receives public uncertainty without hidden verdict or truth',
    () async {
      final gateway = _FakeModelGateway('{"text":"无法确定。可以把问题拆开问。"}');
      final host = RealCharacterHostResponseRenderer(
        modelGateway: gateway,
        identityLoader: (_) async =>
            const CharacterHostIdentity(displayName: '老裴'),
      );
      final target = request(
        GameHostSemanticType.answerPartial,
        TurtleSoupJudgment.partial.canonicalText,
      );
      expect(await host.render(target), contains('无法确定'));
      final prompt = gateway.messages.map((m) => m['content']).join('\n');
      expect(prompt, contains('authoritativeSemantic: answerUnknown'));
      expect(prompt, isNot(contains('answerPartial')));
      expect(prompt, isNot(contains(target.view.hiddenTruth)));
      expect(
        const CharacterHostSemanticConsistencyValidator().isSafe(
          target.view,
          '无法确定，但你已经接近答案了。',
        ),
        isFalse,
      );
    },
  );

  test('semantic validator rejects contradictions', () {
    const validator = CharacterHostSemanticConsistencyValidator();
    expect(
      validator.isSafe(
        request(GameHostSemanticType.answerYes, '是的。').view,
        '不是，换个方向。',
      ),
      isFalse,
    );
    expect(
      validator.isSafe(
        request(GameHostSemanticType.answerNo, '不是。').view,
        '是的，没错。',
      ),
      isFalse,
    );
    expect(
      validator.isSafe(
        request(
          GameHostSemanticType.answerUnknown,
          '这个问题目前无法直接判断，可以再限定一下。',
        ).view,
        '是的，就是这样。',
      ),
      isFalse,
    );
    expect(
      validator.isSafe(
        request(GameHostSemanticType.answerIrrelevant, '这个方向和关键点关系不大。').view,
        '不是。',
      ),
      isFalse,
    );
    expect(
      validator.isSafe(
        request(GameHostSemanticType.answerPartial, '方向有些接近，但还缺少关键条件。').view,
        '是的，完全正确。',
      ),
      isFalse,
    );
    expect(
      validator.isSafe(
        request(GameHostSemanticType.guessCorrect, '答对了！').view,
        '不对，还差一点。',
      ),
      isFalse,
    );
    expect(
      validator.isSafe(
        request(GameHostSemanticType.guessIncorrect, '还差一点。').view,
        '答对了，破汤成功。',
      ),
      isFalse,
    );
  });

  test('hint must retain exact official content without extra clue', () {
    const validator = CharacterHostSemanticConsistencyValidator();
    final view = request(GameHostSemanticType.hint, '她不是普通读者。').view;
    expect(validator.isSafe(view, '（想了想）提示：她不是普通读者。'), isTrue);
    expect(validator.isSafe(view, '她不是普通读者，她其实是志愿者。'), isFalse);
  });

  test('engine canonical wording for every judgment stays consistent', () {
    const validator = CharacterHostSemanticConsistencyValidator();
    for (final judgment in TurtleSoupJudgment.values) {
      expect(
        validator.isSafe(
          request(judgment.semanticType, judgment.canonicalText).view,
          judgment.canonicalText,
        ),
        isTrue,
        reason: judgment.name,
      );
    }
  });

  test('truth is blocked before reveal and accepted when authorized', () {
    const validator = CharacterHostSemanticConsistencyValidator();
    final hidden = request(GameHostSemanticType.answerYes, '是的。');
    expect(validator.isSafe(hidden.view, hidden.view.hiddenTruth), isFalse);
    final reveal = request(
      GameHostSemanticType.reveal,
      hidden.view.hiddenTruth,
      reveal: true,
    );
    expect(
      validator.isSafe(reveal.view, '（翻开答案）${reveal.view.hiddenTruth}'),
      isTrue,
    );
  });

  test(
    'malformed empty oversized provider error and timeout fail safely',
    () async {
      final target = request(GameHostSemanticType.answerYes, '是的。');
      for (final output in [
        'not json',
        '{}',
        jsonEncode({'text': ''}),
        jsonEncode({'text': '是${List.filled(200, '很').join()}'}),
        jsonEncode({'text': '是的。', 'semantic': 'no'}),
      ]) {
        expect(
          () => renderer(output).render(target),
          throwsA(isA<Exception>()),
        );
      }
      expect(
        () => renderer('', fail: true).render(target),
        throwsA(isA<Exception>()),
      );
      final completer = Completer<String>();
      final timeoutRenderer = RealCharacterHostResponseRenderer(
        modelGateway: _WaitingGateway(completer.future),
        identityLoader: (_) async =>
            const CharacterHostIdentity(displayName: '老裴'),
        timeout: Duration.zero,
      );
      expect(
        () => timeoutRenderer.render(target),
        throwsA(isA<CharacterHostRenderFailure>()),
      );
    },
  );

  test('missing registry identity fails before provider call', () async {
    final gateway = _FakeModelGateway(jsonEncode({'text': '是的。'}));
    final target = RealCharacterHostResponseRenderer(
      modelGateway: gateway,
      identityLoader: (_) async => null,
    );
    expect(
      () => target.render(request(GameHostSemanticType.answerYes, '是的。')),
      throwsA(isA<CharacterHostRenderFailure>()),
    );
    expect(gateway.calls, 0);
  });
}

class _FakeModelGateway implements CharacterHostModelGateway {
  _FakeModelGateway(this.response, {this.fail = false});
  final String response;
  final bool fail;
  int calls = 0;
  List<Map<String, dynamic>> messages = const [];

  @override
  Future<String> complete({
    required List<Map<String, dynamic>> messages,
  }) async {
    calls++;
    this.messages = messages;
    if (fail) throw StateError('provider failed');
    return response;
  }
}

class _WaitingGateway implements CharacterHostModelGateway {
  const _WaitingGateway(this.future);
  final Future<String> future;
  @override
  Future<String> complete({required List<Map<String, dynamic>> messages}) =>
      future;
}

class _CompletingRenderer implements CharacterHostResponseRenderer {
  const _CompletingRenderer(this.future);
  final Future<String> future;
  @override
  Future<String> render(CharacterHostRenderRequest request) => future;
}
