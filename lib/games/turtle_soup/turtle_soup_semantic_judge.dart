import 'dart:async';
import 'dart:convert';

import '../../ai/model_hub.dart';
import '../../models/ai_capability.dart';
import '../hosting/character_host_agent.dart';
import 'turtle_soup_logic_profile.dart';
import 'turtle_soup_models.dart';
import 'turtle_soup_semantic_decision.dart';
import 'turtle_soup_guess_decision.dart';

/// Engine authoritative verdict for a player question.
///
/// 判定只描述「玩家问题与官方汤底的关系」。它不包含主持台词、提示、汤底内容
/// 或任何 Session 状态，Host Renderer 只能改写表达方式，不能改写判定。
enum TurtleSoupJudgment {
  /// 问题中的陈述与汤底明确一致。
  yes,

  /// 问题中的陈述与汤底明确冲突。
  no,

  /// 问题可以理解，但答案对破解当前谜题没有实际关系。
  irrelevant,

  /// 方向包含正确成分，但表述过宽或混入错误前提，不能直接回答 yes。
  partial,

  /// 只有依据权威汤底确实无法判断时才使用，属于低频兜底。
  uncertain,
}

extension TurtleSoupJudgmentSemantics on TurtleSoupJudgment {
  GameHostSemanticType get semanticType => switch (this) {
    TurtleSoupJudgment.yes => GameHostSemanticType.answerYes,
    TurtleSoupJudgment.no => GameHostSemanticType.answerNo,
    TurtleSoupJudgment.irrelevant => GameHostSemanticType.answerIrrelevant,
    TurtleSoupJudgment.partial => GameHostSemanticType.answerPartial,
    TurtleSoupJudgment.uncertain => GameHostSemanticType.answerUnknown,
  };

  /// canonical 文案按判定语义区分，避免所有非 YES/NO 都显示同一句。
  String get canonicalText => switch (this) {
    TurtleSoupJudgment.yes => '是的。',
    TurtleSoupJudgment.no => '不是。',
    TurtleSoupJudgment.irrelevant => '无关。',
    TurtleSoupJudgment.partial => '无法确定。可以把问题拆开问。',
    TurtleSoupJudgment.uncertain => '无法确定。',
  };

  GameHostSemanticResult get semanticResult =>
      GameHostSemanticResult(type: semanticType, canonicalText: canonicalText);
}

/// Authoritative material the Judge is allowed to read.
///
/// 这些字段属于 Engine authority boundary，只能进入 Judge 请求，
/// 绝不能进入 Player Knowledge View / Timeline / Bubble。
class TurtleSoupJudgeRequest {
  const TurtleSoupJudgeRequest({
    required this.puzzle,
    required this.question,
    this.recentPublicContext = const [],
  });

  final TurtleSoupPuzzle puzzle;
  final String question;

  /// 最近公开问题/回答等，仅用于消解指代，不含隐藏真相。
  final List<String> recentPublicContext;
}

abstract interface class TurtleSoupSemanticJudge {
  /// 返回 null 表示裁判没有给出合法判定，Engine 必须走安全兜底。
  Future<TurtleSoupJudgment?> judge(TurtleSoupJudgeRequest request);
}

/// Optional extension used only by profiled puzzles. Legacy/fake judges can
/// keep implementing [TurtleSoupSemanticJudge] and produce empty metadata.
abstract interface class TurtleSoupSemanticDecisionJudge {
  Future<TurtleSoupSemanticDecision?> judgeDecision(
    TurtleSoupJudgeRequest request,
    TurtleSoupLogicProfile profile,
  );
}

/// Model gateway boundary. 复用 ModelHub chatProvider()，不新增 Provider 配置。
abstract interface class SemanticJudgeModelGateway {
  Future<String> complete({required List<Map<String, dynamic>> messages});
}

abstract interface class SemanticDecisionJudgeModelGateway {
  Future<String> completeDecision({
    required List<Map<String, dynamic>> messages,
  });
}

abstract interface class SemanticGuessJudgeModelGateway {
  Future<String> completeGuess({required List<Map<String, dynamic>> messages});
}

class ModelHubSemanticJudgeModelGateway
    implements
        SemanticJudgeModelGateway,
        SemanticDecisionJudgeModelGateway,
        SemanticGuessJudgeModelGateway {
  ModelHubSemanticJudgeModelGateway({ModelHub? modelHub})
    : _modelHub = modelHub ?? ModelHub();

  final ModelHub _modelHub;

  @override
  Future<String> completeGuess({
    required List<Map<String, dynamic>> messages,
  }) => _complete(messages: messages, maxTokens: 350);

  @override
  Future<String> complete({required List<Map<String, dynamic>> messages}) =>
      _complete(messages: messages, maxTokens: 32);

  @override
  Future<String> completeDecision({
    required List<Map<String, dynamic>> messages,
  }) => _complete(messages: messages, maxTokens: 96);

  Future<String> _complete({
    required List<Map<String, dynamic>> messages,
    required int maxTokens,
  }) async {
    if (!await _modelHub.isConfigured(AiCapability.chat)) {
      throw const SemanticJudgeUnavailable();
    }
    final provider = await _modelHub.chatProvider();
    return provider.complete(
      messages: messages,
      // 判定任务只要求低温度、短结构化输出，不做第二次 self-check。
      temperature: 0,
      maxTokens: maxTokens,
      acceptStructuredReasoningFallback: true,
    );
  }
}

class SemanticJudgeUnavailable implements Exception {
  const SemanticJudgeUnavailable();
  @override
  String toString() => '聊天模型未配置，海龟汤语义裁判不可用。';
}

/// LLM Semantic Judge: 只输出严格结构化判定，不生成主持台词。
class ModelTurtleSoupSemanticJudge
    implements
        TurtleSoupSemanticJudge,
        TurtleSoupSemanticDecisionJudge,
        TurtleSoupGuessJudge {
  ModelTurtleSoupSemanticJudge({
    SemanticJudgeModelGateway? gateway,
    this.timeout = const Duration(seconds: 8),
  }) : _gateway = gateway ?? ModelHubSemanticJudgeModelGateway();

  final SemanticJudgeModelGateway _gateway;
  final Duration timeout;

  @override
  Future<bool> judgeGuess(TurtleSoupGuessRequest request) async {
    if (request.guess.trim().isEmpty) return false;
    try {
      final messages = <Map<String, dynamic>>[
        {
          'role': 'system',
          'content':
              '''判断本次 Guess 自身是否完整表达官方解法。接受同义改写、语序变化与隐含在完整因果句中的事实，不要求逐字匹配。
逐项判断事实和因果是否得到表达；关键词堆砌、否定正确事实、错误来源、缺少核心原因均不能 solved。不得让历史进度代替本次 Guess。
只返回 JSON：{"solved":bool,"coverage":["合法标准ID"],"missing":["合法标准ID"],"contradiction":bool}。
coverage 与 missing 必须无重复、无交集且合计覆盖全部标准。只有全部覆盖且无核心矛盾才能 solved=true。不要输出解释。''',
        },
        {
          'role': 'user',
          'content': jsonEncode({
            'truth': request.puzzle.truth,
            'criteria': request.criteria,
            'facts': {
              for (final f in request.profile?.facts ?? <PuzzleFact>[])
                f.id: f.statement,
            },
            'guess': request.guess,
          }),
        },
      ];
      final gateway = _gateway;
      final completion = gateway is SemanticGuessJudgeModelGateway
          ? (gateway as SemanticGuessJudgeModelGateway).completeGuess(
              messages: messages,
            )
          : gateway.complete(messages: messages);
      return parseTurtleSoupGuessDecision(
        await completion.timeout(timeout),
        request.criteria.keys.toSet(),
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Future<TurtleSoupJudgment?> judge(TurtleSoupJudgeRequest request) async {
    if (request.question.trim().isEmpty) return null;
    try {
      final raw = await _gateway
          .complete(messages: _messages(request))
          .timeout(timeout);
      return parseTurtleSoupJudgment(raw);
    } catch (_) {
      // provider 未配置 / 超时 / 网络失败 / 异常：一律降级为 Engine 兜底，
      // 模型失败不能让游戏报错或卡死。
      return null;
    }
  }

  @override
  Future<TurtleSoupSemanticDecision?> judgeDecision(
    TurtleSoupJudgeRequest request,
    TurtleSoupLogicProfile profile,
  ) async {
    if (request.question.trim().isEmpty ||
        request.puzzle.id != profile.puzzleId) {
      return null;
    }
    try {
      final messages = _decisionMessages(request, profile);
      final gateway = _gateway;
      final completion = gateway is SemanticDecisionJudgeModelGateway
          ? (gateway as SemanticDecisionJudgeModelGateway).completeDecision(
              messages: messages,
            )
          : gateway.complete(messages: messages);
      final raw = await completion.timeout(timeout);
      return parseTurtleSoupSemanticDecision(raw, profile);
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> _messages(TurtleSoupJudgeRequest request) => [
    {'role': 'system', 'content': _systemPrompt},
    {'role': 'user', 'content': _userPrompt(request)},
  ];

  List<Map<String, dynamic>> _decisionMessages(
    TurtleSoupJudgeRequest request,
    TurtleSoupLogicProfile profile,
  ) => [
    {'role': 'system', 'content': _decisionSystemPrompt},
    {'role': 'user', 'content': _decisionUserPrompt(request, profile)},
  ];

  String _userPrompt(TurtleSoupJudgeRequest request) {
    final context = request.recentPublicContext.isEmpty
        ? '暂无公开记录'
        : request.recentPublicContext
              .map((item) => '- ${_limit(item, 120)}')
              .join('\n');
    return '''
汤面：${request.puzzle.surface}
官方汤底：${request.puzzle.truth}
必须还原的真相要点：${request.puzzle.requiredTruthPoints.join('、')}
推理维度：${request.puzzle.reasoningDimensions.isEmpty ? '未提供' : request.puzzle.reasoningDimensions.join('、')}
最近公开上下文：
$context
玩家问题：${_limit(request.question, 220)}
'''
        .trim();
  }

  String _decisionUserPrompt(
    TurtleSoupJudgeRequest request,
    TurtleSoupLogicProfile profile,
  ) {
    final base = _userPrompt(request);
    final facts = profile.facts
        .map((item) => '${item.id}: ${item.statement}')
        .join('\n');
    final edges = profile.causalEdges
        .map(
          (item) =>
              '${item.id}: ${item.sourceFactIds.join('+')} ${item.relation.name} ${item.targetFactId}',
        )
        .join('\n');
    final directions = profile.directions
        .map(
          (item) => '${item.id} [${item.kind.name}]: ${item.hiddenDescription}',
        )
        .join('\n');
    return '''
$base

合法事实节点：
$facts
合法因果边：
$edges
合法推理方向：
$directions
'''
        .trim();
  }

  static const _systemPrompt = '''
你是海龟汤的权威语义裁判。你的唯一任务是判定「玩家问题所陈述的内容」与「官方汤底」的关系。
你不回答题目，不生成主持台词，不给提示，不透露汤底，不输出任何解释。

判定枚举（结论只能是其中一个）：
yes：问题中的陈述与汤底明确一致。
no：问题中的陈述与汤底明确冲突，汤底排除了该说法。
partial：方向包含正确成分，但表述过宽，或混入正确与错误前提，不能直接回答 yes。
irrelevant：问题本身可以理解，但其答案与破解当前谜题没有实际关系。
uncertain：只有依据汤底确实无法判断时才使用，必须低频，不得作为默认结论。

判定要求：
1. 只依据用户消息里的汤面、官方汤底和真相要点，不要臆测，不要引入新设定。
2. 玩家问题可能相当具体（例如问某个信号、某件物品的用途、某个身份的识别方式）。只要汤底明确支持或排除了该说法，就必须给出 yes 或 no，不要回答 uncertain。
3. 问题同时包含正确线索与错误前提时给 partial。
4. 与破汤无关的细节（价格、姓名、天气、口味等）给 irrelevant。
5. 不得输出理由、台词、提示、汤底内容或任何额外字段。

只输出严格 JSON，且只能有一个字段：
{"judgment":"yes|no|irrelevant|partial|uncertain"}
''';

  static const _decisionSystemPrompt = '''
你是海龟汤的权威语义裁判。一次完成判定与逻辑节点映射，不生成主持台词，不给提示，不透露汤底。

judgment 仍只能是 yes、no、irrelevant、partial、uncertain。
必须整体判断复合命题。只有所有重要子命题及因果前提都获 truth 支持才能 YES；不得 correct sub-clause + unsupported premise → YES。
部分核心成立但包含未知/不成立的重要附加前提，返回 partial 或 uncertain；整个命题明确被排除才返回 no。
例如低温环境成立，不代表曾接触某个特定低温物体；“接触低温物体导致水迹”不能仅因“低温”正确而回答 yes。
validBranch 是有效方向，misconception 是错误前提或低价值方向，不是权威事实。只根据公开问答足以证明的命题产生 effects：not A 不等于 B，排除杯内漏水不能确认冷凝来源。
confirmFact/resolveEdge 必须有本次问答充分证据支持整个节点/因果关系；未知重要前提不能被隐藏事实自动补齐。
只依据 authoritative truth、Logic Profile 与已公开上下文；公开上下文用于理解问题，玩家假设或先前回答不能补写官方真相。
truth 明确支持或必然推出才是 yes；明确排除才是 no；部分成立为 partial；与解谜无关为 irrelevant；truth 未说明且无法可靠推出为 uncertain。
禁止“也有可能，所以 YES”，禁止为使故事合理自行补世界事实。缺乏依据也不能擅自改成 NO。
例如空杯题的 truth 没有说明杯子装过除水以外的液体，问此历史事实应返回 uncertain、effects=[]；不要把未知液体当成低温来源。
effects 只能使用下列类型：confirmFact、partialFact、rejectDirection、resolveEdge、exhaustDirection。
ref 只能从用户消息提供的合法 opaque ID 中原样选择。不得创建 ID、公开文本、解释或额外字段。
当一个问题同时确认事实与已定义因果关系时，必须返回全部适用 effects；不要只返回 confirmFact 而遗漏同一句已经明确成立的 resolveEdge。

映射依据是问题真实语义与权威事实，而不是问题表面肯定/否定形式。例如询问“设备坏了吗”得到 no，与询问“设备正常吗”得到 yes，都可以 confirmFact 同一个“设备正常”事实。
uncertain 必须返回空 effects。irrelevant 不得确认事实或解析因果边。没有可靠映射时返回空 effects。

只输出严格 JSON：
{"judgment":"yes|no|irrelevant|partial|uncertain","effects":[{"type":"confirmFact|partialFact|rejectDirection|resolveEdge|exhaustDirection","ref":"f01|e01|d01"}]}
''';

  static String _limit(String value, int limit) {
    final trimmed = value.trim();
    return trimmed.length <= limit ? trimmed : trimmed.substring(0, limit);
  }
}

/// 严格解析 Judge 输出：非法 enum、空输出、多字段、非 JSON 一律返回 null。
TurtleSoupJudgment? parseTurtleSoupJudgment(String raw) {
  try {
    final decoded = jsonDecode(_stripFence(raw));
    if (decoded is! Map || decoded.length != 1) return null;
    final value = decoded['judgment'];
    if (value is! String) return null;
    final name = value.trim().toLowerCase();
    for (final judgment in TurtleSoupJudgment.values) {
      if (judgment.name == name) return judgment;
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// Parses a profiled Judge response. A valid judgment survives malformed or
/// illegal effects; effect validation is deliberately all-or-nothing.
TurtleSoupSemanticDecision? parseTurtleSoupSemanticDecision(
  String raw,
  TurtleSoupLogicProfile profile, {
  TurtleSoupDecisionEffectValidator validator =
      const TurtleSoupDecisionEffectValidator(),
}) {
  try {
    final decoded = jsonDecode(_stripFence(raw));
    if (decoded is! Map) return null;
    if (decoded.keys.any((key) => key != 'judgment' && key != 'effects')) {
      return null;
    }
    final value = decoded['judgment'];
    if (value is! String) return null;
    final name = value.trim().toLowerCase();
    final judgment = TurtleSoupJudgment.values
        .where((item) => item.name == name)
        .firstOrNull;
    if (judgment == null) return null;

    final rawEffects = decoded['effects'];
    if (rawEffects == null) {
      return TurtleSoupSemanticDecision(judgment: judgment);
    }
    if (rawEffects is! List) {
      return TurtleSoupSemanticDecision(judgment: judgment);
    }
    final effects = <BoundaryEffect>[];
    for (final rawEffect in rawEffects) {
      if (rawEffect is! Map ||
          rawEffect.length != 2 ||
          rawEffect['type'] is! String ||
          rawEffect['ref'] is! String) {
        return TurtleSoupSemanticDecision(judgment: judgment);
      }
      final typeName = (rawEffect['type'] as String).trim();
      final type = BoundaryEffectType.values
          .where((item) => item.name == typeName)
          .firstOrNull;
      if (type == null) {
        return TurtleSoupSemanticDecision(judgment: judgment);
      }
      effects.add(
        BoundaryEffect(
          type: type,
          targetId: (rawEffect['ref'] as String).trim(),
        ),
      );
    }
    final validated = validator.validate(
      profile: profile,
      judgment: judgment,
      effects: effects,
    );
    return TurtleSoupSemanticDecision(
      judgment: judgment,
      effects: validated.length == effects.length ? validated : const [],
    );
  } catch (_) {
    return null;
  }
}

String _stripFence(String value) => value
    .trim()
    .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
    .replaceFirst(RegExp(r'\s*```$'), '')
    .trim();
