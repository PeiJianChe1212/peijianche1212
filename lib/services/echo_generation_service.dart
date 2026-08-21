import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../ai/model_hub.dart';
import '../ai/providers/openai_compatible_chat_provider.dart';
import '../models/ai_character.dart';
import '../models/echo_draft.dart';
import '../models/life_moment.dart';
import '../models/story_fragment.dart';
import 'ai_social_protocol_service.dart';
import 'api_settings_storage_service.dart';
import 'character_settings_storage_service.dart';
import 'character_profile_storage_service.dart';
import 'context_builder.dart';
import 'character_registry_service.dart';
import 'character_relationship_context_service.dart';
import 'life_decision_engine_service.dart';
import 'life_engine_service.dart';
import 'life_event_pool_service.dart';
import 'moment_engine_service.dart';
import 'narrative_engine_service.dart';
import 'story_fragment_engine_service.dart';
import 'life_moment_storage_service.dart';
import 'echo_expression_prompt.dart';
import 'echo_image_intent_service.dart';
import 'echo_image_prompt.dart';
import 'structured_model_output_exception.dart';
import 'developer_environment_service.dart';

class EchoNoMomentException implements Exception {
  const EchoNoMomentException();

  @override
  String toString() => '暂时没有新的生活瞬间';
}

class EchoDraftGenerationException implements Exception {
  const EchoDraftGenerationException();

  @override
  String toString() => '本次生成失败，请重新生成';
}

String echoDraftUserMessage(Object error) {
  if (error is EchoNoMomentException) return error.toString();
  if (error is EchoDraftGenerationException ||
      error is StructuredModelOutputException ||
      error is ChatEmptyResponseException ||
      error is FormatException) {
    return '本次生成失败，请重新生成';
  }
  if (error is StateError && error.toString().contains('设置 → 模型与 API')) {
    return '请先在“设置 → 模型与 API”中完成聊天模型配置。';
  }
  return '本次生成失败，请重新生成';
}

class EchoGenerationService {
  EchoGenerationService({required this.character, http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null {
    _modelHub = ModelHub(client: _client);
    _decisionEngine = LifeDecisionEngineService(
      character: character,
      client: _client,
    );
    _lifeEngine = LifeEngineService(character: character, client: _client);
    _momentEngine = MomentEngineService(character: character, client: _client);
    _eventPool = LifeEventPoolService(characterId: character.id);
  }

  final AiCharacter character;
  final http.Client _client;
  final bool _ownsClient;
  late final ModelHub _modelHub;
  late final LifeDecisionEngineService _decisionEngine;
  late final LifeEngineService _lifeEngine;
  late final MomentEngineService _momentEngine;
  late final LifeEventPoolService _eventPool;

  final ApiSettingsStorageService _apiStorage = ApiSettingsStorageService();

  EchoMomentDecision? _lastDecision;

  EchoMomentDecision? get lastDecision => _lastDecision;

  Future<EchoDraft> generateDraft() async {
    try {
      final draft = await tryGenerateDraft(manualRequest: true);
      if (draft == null) {
        throw const EchoNoMomentException();
      }
      return draft;
    } on EchoNoMomentException {
      rethrow;
    } on StructuredModelOutputException {
      throw const EchoDraftGenerationException();
    } on ChatEmptyResponseException {
      throw const EchoDraftGenerationException();
    } on FormatException {
      throw const EchoDraftGenerationException();
    }
  }

  Future<EchoDraft?> tryGenerateDraft({bool manualRequest = false}) async {
    final apiSettings = await _apiStorage.loadSettings();
    if (!apiSettings.isConfigured) {
      throw StateError('请先在“设置 → 模型与 API”中填写并保存接口配置。');
    }

    if (await _eventPool.shouldRefill()) {
      await _refillEventPool();
    }

    var events = await _eventPool.loadAvailable(limit: 8);
    if (events.isEmpty) {
      final nextPendingAt = await _eventPool.nextPendingAt();
      if (nextPendingAt != null) {
        throw const EchoNoMomentException();
      }

      await _refillEventPool();
      events = await _eventPool.loadAvailable(limit: 8);
    }
    if (events.isEmpty) {
      final nextPendingAt = await _eventPool.nextPendingAt();
      if (nextPendingAt != null) {
        throw const EchoNoMomentException();
      }
      throw const EchoNoMomentException();
    }

    final decision = await _runStage(
      'Moment Engine',
      () => _momentEngine.chooseMoment(events, manualRequest: manualRequest),
    );
    _lastDecision = decision;
    if (!decision.shouldShare) return null;

    return _generateForDecision(decision);
  }

  /// One bounded rewrite of the already selected moment. It does not rerun
  /// Life or Moment selection and therefore cannot switch to a different fact.
  Future<EchoDraft?> retryLastDraft({required String previousContent}) async {
    final decision = _lastDecision;
    if (decision == null || !decision.shouldShare) return null;
    return _generateForDecision(decision, avoidContent: previousContent);
  }

  Future<EchoDraft> _generateForDecision(
    EchoMomentDecision decision, {
    String avoidContent = '',
  }) async {
    final settings = await CharacterSettingsStorageService(
      characterId: character.id,
    ).loadSettings();
    final profile = await CharacterProfileStorageService(
      characterId: character.id,
    ).load(character: character, legacySettings: settings);
    final storedMoments = await LifeMomentStorageService(
      characterId: character.id,
    ).loadItems();
    final narrative = await _runStage('Story Fragment / Narrative', () async {
      final fragment = const StoryFragmentEngineService().buildAround(
        decision.candidate,
        [...storedMoments, decision.candidate],
      );
      return const NarrativeEngineService().render(
        fragment,
        perspective: NarrativePerspective.echo,
      );
    });
    final registeredCharacters = await CharacterRegistryService()
        .loadCharacters();
    final relationshipPrompt = await CharacterRelationshipContextService()
        .buildPromptSection(
          currentCharacter: character,
          allCharacters: registeredCharacters,
        );
    final socialProtocolPrompt = AiSocialProtocolService.buildPromptSection(
      currentCharacter: character,
      allCharacters: registeredCharacters,
    );
    final provider = await _modelHub.chatProvider();
    final raw = await _runStage(
      'Echo Generation',
      () => provider.complete(
        messages: [
          {
            'role': 'system',
            'content': ContextBuilder.build(
              task: ContextTask.echo,
              settings: settings,
              taskRules: EchoExpressionPrompt.rules(),
              expressionProfile: EchoExpressionPrompt.expressionProfile(
                profile: profile,
              ),
              relationshipContext: relationshipPrompt,
              socialProtocol: socialProtocolPrompt,
              includeBehaviorRules: false,
              sourceFacts: _echoFacts(
                decision: decision,
                officialNarrative: narrative.content,
              ),
            ),
          },
          {
            'role': 'user',
            'content': EchoExpressionPrompt.userInstruction(
              avoidContent: avoidContent,
            ),
          },
        ],
        temperature: settings.temperature.clamp(0.64, 0.84).toDouble(),
        maxTokens: 420,
        topP: 0.9,
      ),
    );

    final cleaned = _clean(raw);
    if (cleaned.isEmpty) {
      throw const FormatException('模型没有生成有效的 Echo 内容。');
    }

    final moment = decision.candidate;
    final imageIntent = const EchoImageIntentService().resolve(
      moment: moment,
      characterId: character.id,
      suggestedByMoment: decision.suggestImage,
    );
    final imagePrompt = EchoImagePrompt.build(
      intent: imageIntent,
      characterProfile: imageIntent.requiredCharacterIds.isEmpty
          ? null
          : profile,
    );

    return EchoDraft(
      content: cleaned,
      momentSummary: decision.reason.trim().isEmpty
          ? moment.shareHook.trim()
          : decision.reason.trim(),
      shouldAttachImage:
          imageIntent.shouldGenerateImage && imagePrompt.isNotEmpty,
      imageScene: imageIntent.visualFocus,
      imagePrompt: imagePrompt,
      imageIntent: imageIntent,
    );
  }

  Future<void> _refillEventPool() async {
    final decisions = await _runStage(
      'Life Decision Engine',
      () => _decisionEngine.decide(maxDecisions: 4),
    );
    if (decisions.isEmpty) return;

    final realizedEvents = await _runStage(
      'Life Engine',
      () => _lifeEngine.generateFromDecisions(decisions),
    );
    await _eventPool.addEvents(realizedEvents);
  }

  Future<T> _runStage<T>(String stage, Future<T> Function() action) async {
    try {
      return await action();
    } catch (error) {
      await _logStageFailure(stage, error);
      rethrow;
    }
  }

  Future<void> _logStageFailure(String stage, Object error) async {
    try {
      if (!await DeveloperEnvironmentService().isEnabled()) return;
      final details = error is ChatEmptyResponseException
          ? 'empty_response finish=${error.finishReason.isEmpty ? 'unknown' : error.finishReason} reasoning=${error.hasReasoningContent}'
          : error is StructuredModelOutputException
          ? 'malformed_json'
          : error.runtimeType.toString();
      debugPrint('[EchoPipeline] stage=$stage failure=$details');
    } catch (_) {
      // Diagnostics must never replace the original pipeline failure.
    }
  }

  String _echoFacts({
    required EchoMomentDecision decision,
    required String officialNarrative,
  }) {
    final moment = decision.candidate;
    final related = moment.relatedCharacterNames.isEmpty
        ? '无'
        : moment.relatedCharacterNames.join('、');
    return '''
这件事已经由 Life Decision Engine 确定发生，由 Life Engine 落实成生活事件，再由 Moment Engine 选中。

【官方故事片段】
$officialNarrative

【选中的生活瞬间】
场景：${moment.scene}
发生的事：${moment.event}
具体细节：${moment.detail}
当时感受：${moment.feeling}
可能想发布的原因：${moment.shareHook}
可自然提及的人：$related
''';
  }

  String _clean(String raw) {
    var value = raw.trim();
    value = value.replaceFirst(
      RegExp(r'^```(?:text|markdown)?\s*', caseSensitive: false),
      '',
    );
    value = value.replaceFirst(RegExp(r'\s*```$'), '');
    value = value.replaceFirst(RegExp(r'^(Echo|动态|正文|草稿)\s*[:：]\s*'), '');
    if (value.startsWith('"') && value.endsWith('"') && value.length > 1) {
      value = value.substring(1, value.length - 1).trim();
    }
    if (value.startsWith('“') && value.endsWith('”') && value.length > 1) {
      value = value.substring(1, value.length - 1).trim();
    }
    return value;
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
