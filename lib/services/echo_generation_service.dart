import 'package:http/http.dart' as http;

import '../ai/model_hub.dart';
import '../models/ai_character.dart';
import '../models/character_settings.dart';
import '../models/echo_draft.dart';
import '../models/life_moment.dart';
import 'api_settings_storage_service.dart';
import 'character_settings_storage_service.dart';
import 'life_event_pool_service.dart';
import 'moment_engine_service.dart';

class EchoGenerationService {
  EchoGenerationService({
    required this.character,
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null {
    _modelHub = ModelHub(client: _client);
    _lifeEventPool = LifeEventPoolService(
      character: character,
      client: _client,
    );
    _momentEngine = MomentEngineService(character: character, client: _client);
  }

  final AiCharacter character;
  final http.Client _client;
  final bool _ownsClient;
  late final ModelHub _modelHub;
  late final LifeEventPoolService _lifeEventPool;
  late final MomentEngineService _momentEngine;

  final ApiSettingsStorageService _apiStorage = ApiSettingsStorageService();

  EchoMomentDecision? _lastDecision;

  EchoMomentDecision? get lastDecision => _lastDecision;

  Future<EchoDraft> generateDraft() async {
    final apiSettings = await _apiStorage.loadSettings();
    if (!apiSettings.isConfigured) {
      throw StateError('请先在“设置 → 模型与 API”中填写并保存接口配置。');
    }

    final previousId = _lastDecision?.candidate.id;
    final candidates = await _lifeEventPool.getCandidates(
      count: 4,
      excludeIds: previousId == null ? <String>{} : {previousId},
    );
    final decision = await _momentEngine.chooseMoment(
      candidates,
      manualRequest: true,
    );
    _lastDecision = decision;

    final settings = await CharacterSettingsStorageService(
      characterId: character.id,
    ).loadSettings();
    final provider = await _modelHub.chatProvider();
    final raw = await provider.complete(
      messages: [
        {
          'role': 'system',
          'content': _buildDraftPrompt(
            settings: settings,
            decision: decision,
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

  String _buildDraftPrompt({
    required CharacterSettings settings,
    required EchoMomentDecision decision,
  }) {
    final moment = decision.candidate;
    final related = moment.relatedCharacterNames.isEmpty
        ? '无'
        : moment.relatedCharacterNames.join('、');

    return '''
你正在为 PeiLink 的 Echo 写一条角色动态。生活片段已经由 Life Engine 产生，并由 Moment Engine 选中。你只负责把它写成自然正文。

【角色身份】
${settings.coreProfile}

【角色表达方式】
${settings.behaviorStyle}

【角色禁用规则】
${settings.forbiddenRules}

【选中的生活瞬间】
场景：${moment.scene}
发生的事：${moment.event}
具体细节：${moment.detail}
当时感受：${moment.feeling}
值得分享的原因：${moment.shareHook}
可自然提及的人：$related
Moment 评分：${decision.score.toStringAsFixed(0)}

【写作原则】
1. Echo 是角色自己的生活主页，不是聊天回复，也不是写给用户的情书。
2. 把重点放在“具体细节和余味”上，不要流水账复述整个事件。
3. 可以有轻微吐槽、停顿、反差和普通人的不完美。
4. 不要用“今天我去了……然后……”的作文腔，不要总结人生道理。
5. 不要机械提当前时间，不要为了生活感硬写早中晚。
6. 不要称呼${settings.userCallName}，不要提问，不要邀请对方回复。
7. 不使用括号动作、小说旁白、舞台指令、标题、标签或 Markdown。
8. 只输出动态正文，20 至 180 个汉字，一到三小段。
9. “可自然提及的人”不为“无”时，也只有在这条动态读起来确实自然时才可 @ 一次；格式必须是“@名字”。不要句句都 @，也不要在正文末尾单独挂一个名字。
10. “可自然提及的人”为“无”时，绝对不要自行创造 @ 对象。
11. 不要虚构片段之外的真实地点、天气、新闻和品牌。
''';
  }

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

  Future<void> markLastMomentUsed() async {
    final id = _lastDecision?.candidate.id;
    if (id == null || id.trim().isEmpty) return;
    await _lifeEventPool.markUsed(id);
  }

  void dispose() {
    _lifeEventPool.dispose();
    if (_ownsClient) _client.close();
  }
}
