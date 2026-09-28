import 'dart:async';
import 'dart:convert';

import '../../ai/model_hub.dart';
import '../hosting/character_host_agent.dart';

abstract interface class CharacterHostModelGateway {
  Future<String> complete({required List<Map<String, dynamic>> messages});
}

class ModelHubCharacterHostModelGateway implements CharacterHostModelGateway {
  ModelHubCharacterHostModelGateway({ModelHub? modelHub})
    : _modelHub = modelHub ?? ModelHub();

  final ModelHub _modelHub;

  @override
  Future<String> complete({
    required List<Map<String, dynamic>> messages,
  }) async {
    final provider = await _modelHub.chatProvider();
    return provider.complete(
      messages: messages,
      temperature: 0.25,
      maxTokens: 180,
    );
  }
}

CharacterHostResponseRenderer createProductionCharacterHostRenderer({
  CharacterHostIdentityLoader? identityLoader,
}) => RealCharacterHostResponseRenderer(identityLoader: identityLoader);

typedef DeferredCharacterHostResponseCallback =
    Future<void> Function(
      CharacterHostRenderRequest request,
      String text,
      int epoch,
    );

class DeferredCharacterHostResponseRenderer
    implements CharacterHostResponseRenderer {
  const DeferredCharacterHostResponseRenderer({
    required this.delegate,
    required this.onRendered,
    required this.epochProvider,
  });

  final CharacterHostResponseRenderer delegate;
  final DeferredCharacterHostResponseCallback onRendered;
  final int Function() epochProvider;

  @override
  Future<String> render(CharacterHostRenderRequest request) async {
    unawaited(_render(request, epochProvider()));
    return request.view.semanticResult.canonicalText;
  }

  Future<void> _render(CharacterHostRenderRequest request, int epoch) async {
    try {
      final text = await delegate.render(request);
      await Future<void>.delayed(Duration.zero);
      await onRendered(request, text, epoch);
    } catch (_) {
      // The canonical Engine response has already been committed.
    }
  }
}

class RealCharacterHostResponseRenderer
    implements CharacterHostResponseRenderer {
  RealCharacterHostResponseRenderer({
    CharacterHostModelGateway? modelGateway,
    CharacterHostIdentityLoader? identityLoader,
    this.timeout = const Duration(seconds: 15),
    this.maxCharacters = 160,
  }) : _modelGateway = modelGateway ?? ModelHubCharacterHostModelGateway(),
       _identityLoader =
           identityLoader ?? const SafeCharacterHostIdentityLoader().call;

  final CharacterHostModelGateway _modelGateway;
  final CharacterHostIdentityLoader _identityLoader;
  final Duration timeout;
  final int maxCharacters;

  @override
  Future<String> render(CharacterHostRenderRequest request) async {
    try {
      final identity = await _identityLoader(request.characterId);
      if (identity == null) throw const CharacterHostRenderFailure();
      final raw = await _modelGateway
          .complete(messages: _messages(request, identity))
          .timeout(timeout);
      final text = _parse(raw);
      final validator = CharacterHostSemanticConsistencyValidator(
        maxCharacters: maxCharacters,
      );
      if (!validator.isSafe(request.view, text)) {
        throw const CharacterHostRenderFailure();
      }
      return text;
    } catch (_) {
      throw const CharacterHostRenderFailure();
    }
  }

  List<Map<String, dynamic>> _messages(
    CharacterHostRenderRequest request,
    CharacterHostIdentity identity,
  ) => [
    {
      'role': 'system',
      'content':
          '''
你是${identity.displayName}，正在主持海龟汤。你的任务仅是改写 Engine 已确定的主持语义，绝对不能重新判断规则。
玩家名：${request.gameUserIdentity.displayName}。这里只提供共同玩游戏所需的轻量身份，不得补充双方关系、职业、背景或私聊世界剧情。
角色表达白名单：
性格：${_limit(identity.personalityTags, 120)}
说话风格：${_limit(identity.speakingStyle, 180)}

可以使用很短的动作或神态和自然主持措辞，但不要套固定模板，不写长篇角色扮演，不闲聊，不新增事实、线索或解释。
必须保持 authoritative semantic 完全一致。Hint 必须逐字保留正式 hint。Reveal 未授权时不得复述、改写或暗示隐藏真相。
公开语义对照：answerYes=是；answerNo=不是；answerIrrelevant=无关；answerUnknown=无法确定。不得改变公开判定，不评价玩家是否接近答案，不暗示命中了部分真相。
只输出严格 JSON，且只能有 text 一个字段：{"text":"简短主持表达"}
'''
              .trim(),
    },
    {
      'role': 'user',
      'content':
          '''
gameId: ${request.view.gameId}
phase: ${request.view.phase}
trigger: ${request.view.triggerKind}
playerAction: ${_limit(request.view.triggerContent, 220)}
authoritativeSemantic: ${request.view.semanticResult.type == GameHostSemanticType.answerPartial ? GameHostSemanticType.answerUnknown.name : request.view.semanticResult.type.name}
canonicalText: ${request.view.semanticResult.canonicalText}
truthMayBeRevealed: ${request.view.truthMayBeRevealed}
${request.view.truthMayBeRevealed ? 'officialTruth: ${request.view.hiddenTruth}' : ''}
'''
              .trim(),
    },
  ];

  String _parse(String raw) {
    final decoded = jsonDecode(_stripFence(raw));
    if (decoded is! Map ||
        decoded.length != 1 ||
        !decoded.containsKey('text')) {
      throw const CharacterHostRenderFailure();
    }
    final text = decoded['text'];
    if (text is! String || text.trim().isEmpty) {
      throw const CharacterHostRenderFailure();
    }
    return text.trim();
  }

  String _stripFence(String value) => value
      .trim()
      .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
      .replaceFirst(RegExp(r'\s*```$'), '')
      .trim();

  static String _limit(String value, int limit) {
    final trimmed = value.trim();
    return trimmed.length <= limit ? trimmed : trimmed.substring(0, limit);
  }
}

class CharacterHostSemanticConsistencyValidator {
  const CharacterHostSemanticConsistencyValidator({this.maxCharacters = 160});

  final int maxCharacters;

  bool isSafe(CharacterHostKnowledgeView view, String text) {
    final value = text.trim();
    if (value.isEmpty || value.length > maxCharacters) return false;
    if (!view.truthMayBeRevealed && _suspectedTruthLeak(view, value)) {
      return false;
    }
    switch (view.semanticResult.type) {
      case GameHostSemanticType.answerYes:
        return _has(value, const ['是', '对', '没错', '方向对']) &&
            !_has(value, const ['不是', '不对', '错了', '无关']);
      case GameHostSemanticType.answerNo:
        return _has(value, const ['不是', '不对', '否']) &&
            !_has(value, const ['是的', '没错', '猜对', '方向对']);
      case GameHostSemanticType.answerPartial:
      case GameHostSemanticType.answerUnknown:
        return _has(value, const [
              '无法直接判断',
              '无法确定',
              '不确定',
              '拿不准',
              '更具体',
              '限定',
            ]) &&
            !_has(value, const [
              '是的',
              '没错',
              '不是',
              '猜对',
              '接近',
              '方向对',
              '部分正确',
              '差一点',
              '缺少关键',
              '命中',
            ]);
      case GameHostSemanticType.answerIrrelevant:
        return _has(value, const ['无关', '没关系', '关系不大']) &&
            !_has(value, const ['是的', '没错', '不是', '猜对']);
      case GameHostSemanticType.guessIncorrect:
        return _has(value, const ['还差', '不完整', '不对', '再想', '继续']) &&
            !_has(value, const ['答对', '猜对', '成功', '还原了']);
      case GameHostSemanticType.guessCorrect:
        return _has(value, const ['答对', '猜对', '没错', '成功', '还原']) &&
            !_has(value, const ['错误', '不对', '还差', '不完整']);
      case GameHostSemanticType.hint:
        return _safeHint(view.semanticResult.canonicalText, value);
      case GameHostSemanticType.reveal:
        return view.truthMayBeRevealed &&
            _normalize(value).contains(_normalize(view.hiddenTruth));
    }
  }

  bool _safeHint(String officialHint, String output) {
    if (!output.contains(officialHint)) return false;
    var remainder = output.replaceFirst(officialHint, '');
    remainder = remainder.replaceAll(RegExp(r'（[^）]{0,18}）'), '');
    remainder = remainder.replaceAll(
      RegExp(r'[，。！？、：；,.!?\s]|提示|给你|注意|想想|看看|这条|是'),
      '',
    );
    return remainder.isEmpty;
  }

  bool _suspectedTruthLeak(CharacterHostKnowledgeView view, String output) {
    final normalizedOutput = _normalize(output);
    final truth = _normalize(view.hiddenTruth);
    if (truth.length >= 8 &&
        (normalizedOutput.contains(truth) ||
            truth.contains(normalizedOutput))) {
      return true;
    }
    for (final fact in view.protectedFacts) {
      final normalizedFact = _normalize(fact);
      if (normalizedFact.length >= 2 &&
          normalizedOutput.contains(normalizedFact) &&
          !_normalize(view.triggerContent).contains(normalizedFact) &&
          !_normalize(
            view.semanticResult.canonicalText,
          ).contains(normalizedFact)) {
        return true;
      }
    }
    if (truth.length >= 6) {
      for (var index = 0; index <= truth.length - 6; index++) {
        final fragment = truth.substring(index, index + 6);
        if (normalizedOutput.contains(fragment) &&
            !_normalize(view.semanticResult.canonicalText).contains(fragment)) {
          return true;
        }
      }
    }
    return false;
  }

  bool _has(String text, List<String> values) =>
      values.any((value) => text.contains(value));

  String _normalize(String value) =>
      value.replaceAll(RegExp(r'[\s，。！？、：；,.!?（）()“”]'), '');
}

class CharacterHostRenderFailure implements Exception {
  const CharacterHostRenderFailure();
}
