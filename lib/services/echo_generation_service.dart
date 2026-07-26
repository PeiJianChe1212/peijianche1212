import 'package:http/http.dart' as http;

import '../ai/model_hub.dart';
import '../models/ai_character.dart';
import '../models/character_settings.dart';
import '../models/echo_draft.dart';
import '../models/life_moment.dart';
import '../models/story_fragment.dart';
import 'ai_social_protocol_service.dart';
import 'api_settings_storage_service.dart';
import 'character_settings_storage_service.dart';
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

class EchoGenerationService {
  EchoGenerationService({
    required this.character,
    http.Client? client,
  })  : _client = client ?? http.Client(),
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
    final draft = await tryGenerateDraft(manualRequest: true);
    if (draft == null) {
      throw const FormatException('当前没有值得发布的生活瞬间。');
    }
    return draft;
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
        throw FormatException(
          '角色已经有接下来的生活安排，但最近一件事要到'
          '${_formatPendingTime(nextPendingAt)}才真正发生。现在还没有可发布的生活瞬间。',
        );
      }

      await _refillEventPool();
      events = await _eventPool.loadAvailable(limit: 8);
    }
    if (events.isEmpty) {
      final nextPendingAt = await _eventPool.nextPendingAt();
      if (nextPendingAt != null) {
        throw FormatException(
          '新的生活已经安排好，最近一件事会在'
          '${_formatPendingTime(nextPendingAt)}发生。Echo 不会提前剧透。',
        );
      }
      throw const FormatException('当前没有足够依据决定新的生活事件，事件池暂时为空。');
    }

    final decision = await _momentEngine.chooseMoment(
      events,
      manualRequest: manualRequest,
    );
    _lastDecision = decision;
    if (!manualRequest && !decision.shouldShare) return null;

    final settings = await CharacterSettingsStorageService(
      characterId: character.id,
    ).loadSettings();
    final storedMoments = await LifeMomentStorageService(
      characterId: character.id,
    ).loadItems();
    final fragment = const StoryFragmentEngineService().buildAround(
      decision.candidate,
      [...storedMoments, decision.candidate],
    );
    final narrative = const NarrativeEngineService().render(
      fragment,
      perspective: NarrativePerspective.echo,
    );
    final registeredCharacters =
        await CharacterRegistryService().loadCharacters();
    final relationshipPrompt =
        await CharacterRelationshipContextService().buildPromptSection(
      currentCharacter: character,
      allCharacters: registeredCharacters,
    );
    final socialProtocolPrompt = AiSocialProtocolService.buildPromptSection(
      currentCharacter: character,
      allCharacters: registeredCharacters,
    );
    final provider = await _modelHub.chatProvider();
    final raw = await provider.complete(
      messages: [
        {
          'role': 'system',
          'content': ContextBuilder.build(
            task: ContextTask.echo,
            settings: settings,
            taskRules: _echoRules(settings),
            relationshipContext: relationshipPrompt,
            socialProtocol: socialProtocolPrompt,
            sourceFacts: _echoFacts(
              decision: decision,
              officialNarrative: narrative.content,
            ),
          ),
        },
        {
          'role': 'user',
          'content': '把选中的生活瞬间写成一条 Echo。只输出正文。',
        },
      ],
      temperature: settings.temperature.clamp(0.64, 0.84).toDouble(),
      maxTokens: 420,
      topP: 0.9,
    );

    final cleaned = _clean(raw);
    if (cleaned.isEmpty) {
      throw const FormatException('模型没有生成有效的 Echo 内容。');
    }

    final moment = decision.candidate;
    final imageScene = _buildImageScene(moment);

    return EchoDraft(
      content: cleaned,
      momentSummary: decision.reason.trim().isEmpty
          ? moment.shareHook.trim()
          : decision.reason.trim(),
      shouldAttachImage: imageScene.isNotEmpty,
      imageScene: imageScene,
    );
  }

  Future<void> _refillEventPool() async {
    final decisions = await _decisionEngine.decide(maxDecisions: 4);
    if (decisions.isEmpty) return;

    final realizedEvents = await _lifeEngine.generateFromDecisions(decisions);
    await _eventPool.addEvents(realizedEvents);
  }


  String _formatPendingTime(DateTime time) {
    final now = DateTime.now();
    final minute = time.minute.toString().padLeft(2, '0');
    final sameDay = now.year == time.year &&
        now.month == time.month &&
        now.day == time.day;
    if (sameDay) return '今天 ${time.hour}:$minute';

    final tomorrow = DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 1));
    final isTomorrow = tomorrow.year == time.year &&
        tomorrow.month == time.month &&
        tomorrow.day == time.day;
    if (isTomorrow) return '明天 ${time.hour}:$minute';
    return '${time.month}月${time.day}日 ${time.hour}:$minute';
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
值得分享的原因：${moment.shareHook}
可自然提及的人：$related
Moment 评分：${decision.score.toStringAsFixed(0)}
''';
  }

  String _echoRules(CharacterSettings settings) => '''
你正在为 PeiLink 的 Echo 写一条角色动态，只负责把已经发生的真实生活瞬间写成自然正文。
1. Echo 是角色自己的生活主页，不是聊天回复，也不是写给用户的情书。
2. 官方故事片段是唯一叙事依据，只能删减和改写语气，不能增加新事实。
3. 聚焦具体细节和余味，不要流水账、作文腔、人生道理或强行浪漫。
4. 不要机械报时，不要为了生活感硬写早中晚。
5. 不要称呼${settings.userCallName}，不要提问，不要邀请对方回复。
6. 不使用括号动作、小说旁白、舞台指令、标题、标签或 Markdown。
7. 只输出动态正文，20 至 180 个汉字，一到三小段。
8. 只有事实中存在相关人物且正文自然时，才可按“@名字”提及一次。
9. 不得虚构事件之外的地点、天气、新闻、品牌或关系。
''';

  String _buildImageScene(LifeMomentCandidate moment) {
    final parts = <String>[
      moment.scene.trim(),
      moment.event.trim(),
      moment.detail.trim(),
    ].where((value) => value.isNotEmpty).toList();

    if (parts.isEmpty) return '';

    final combined = parts.join('，');
    final unsuitable = RegExp(
      r'纯想法|回忆|梦|抽象|情绪|争吵|危险|受伤|事故',
      caseSensitive: false,
    ).hasMatch(combined);
    if (unsuitable) return '';

    return '$combined。像角色本人用手机随手拍下的生活照片，自然真实，不过度精修，无文字排版。';
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
