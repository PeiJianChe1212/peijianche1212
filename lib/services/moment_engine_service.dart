import 'package:http/http.dart' as http;

import '../ai/model_hub.dart';
import '../models/ai_character.dart';
import '../models/character_settings.dart';
import '../models/echo_item.dart';
import '../models/life_moment.dart';
import 'api_settings_storage_service.dart';
import 'character_settings_storage_service.dart';
import 'echo_storage_service.dart';
import 'context_builder.dart';
import 'structured_model_output_exception.dart';

class MomentEngineService {
  MomentEngineService({required this.character, http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null {
    _modelHub = ModelHub(client: _client);
  }

  final AiCharacter character;
  final http.Client _client;
  final bool _ownsClient;
  late final ModelHub _modelHub;

  final ApiSettingsStorageService _apiStorage = ApiSettingsStorageService();

  Future<EchoMomentDecision> chooseMoment(
    List<LifeMomentCandidate> candidates, {
    bool manualRequest = false,
  }) async {
    if (candidates.isEmpty) {
      throw ArgumentError.value(candidates, 'candidates', '候选不能为空');
    }

    final apiSettings = await _apiStorage.loadSettings();
    if (!apiSettings.isConfigured) {
      throw StateError('请先在“设置 → 模型与 API”中填写并保存接口配置。');
    }

    final settings = await CharacterSettingsStorageService(
      characterId: character.id,
    ).loadSettings();
    final echoes = await EchoStorageService(
      characterId: character.id,
    ).loadItems();
    final provider = await _modelHub.chatProvider();

    final raw = await provider.complete(
      messages: [
        {
          'role': 'system',
          'content': ContextBuilder.build(
            task: ContextTask.momentSelection,
            settings: settings,
            taskRules: buildPrompt(
              settings: settings,
              candidates: candidates,
              echoes: echoes.take(12).toList(),
              manualRequest: manualRequest,
            ),
          ),
        },
        {'role': 'user', 'content': '判断这些生活片段中是否存在值得发布到 Echo 的瞬间。只返回 JSON。'},
      ],
      temperature: 0.42,
      maxTokens: 520,
      topP: 0.82,
      acceptStructuredReasoningFallback: true,
    );

    final decoded = _decodeObject(raw);
    final index = _readInt(
      decoded['selectedIndex'],
      0,
    ).clamp(0, candidates.length - 1).toInt();
    final score = _readDouble(decoded['score'], 0).clamp(0, 100).toDouble();
    final modelShouldShare = decoded['shouldShare'] == true;
    final shouldShare = manualRequest
        ? score >= 48 || modelShouldShare
        : score >= 72 && modelShouldShare;

    return EchoMomentDecision(
      shouldShare: shouldShare,
      score: score,
      reason: decoded['reason']?.toString().trim() ?? '',
      candidate: candidates[index],
      suggestImage: decoded['suggestImage'] == true,
    );
  }

  String buildPrompt({
    required CharacterSettings settings,
    required List<LifeMomentCandidate> candidates,
    required List<EchoItem> echoes,
    required bool manualRequest,
  }) {
    final candidateText = candidates
        .asMap()
        .entries
        .map((entry) {
          final item = entry.value;
          return '''
[${entry.key}]
场景：${item.scene}
事件：${item.event}
细节：${item.detail}
感受：${item.feeling}
分享钩子：${item.shareHook}
''';
        })
        .join('\n');

    final echoText = echoes.isEmpty
        ? '无。'
        : echoes.map((item) => '- ${_truncate(item.content, 180)}').join('\n');

    return '''
你是 PeiLink 的 Moment Engine。你只判断角色是否可能自然地把某个已发生片段发到 Echo，不负责规定正文文风。

【候选片段】
$candidateText

【最近发布过的 Echo】
$echoText

【判断标准】
- 普通状态、吃喝、天气感受、工作摸鱼、吐槽、购物、情绪或一句突然想到的话，都可能成为自然 Echo；不要求值得纪念。
- 具体细节、反差、发现或情绪余味可以提高分享意愿，但都不是必须条件，也不要求形成完整故事。
- 优先选择角色此刻确实可能想说、脱离聊天也能成立，并且与最近 Echo 不重复的片段。
- 不选择尚未发生的安排、纯粹照搬近期聊天、没有任何已发生事实依据或明显重复的内容。

${manualRequest ? '当前是用户主动点击生成草稿；从已有片段中选择一条自然可发的内容即可。' : '当前是自动判断；可以不发，但不要仅因为事情普通或正文可能很短就判定不值得。'}

只返回 JSON：
{
  "shouldShare": true,
  "selectedIndex": 0,
  "score": 0,
  "reason": "一句话说明这个瞬间为什么值得或不值得分享",
  "suggestImage": false
}
''';
  }

  Map<String, dynamic> _decodeObject(String raw) {
    var value = raw.trim();
    value = value.replaceFirst(
      RegExp(r'^```(?:json)?\s*', caseSensitive: false),
      '',
    );
    value = value.replaceFirst(RegExp(r'\s*```$'), '');
    final start = value.indexOf('{');
    final end = value.lastIndexOf('}');
    if (start >= 0 && end > start) {
      value = value.substring(start, end + 1);
    }
    final decoded = decodeStructuredModelJson(value, stage: 'Moment Engine');
    if (decoded is! Map) {
      throw const FormatException('Moment Engine 返回格式不正确。');
    }
    return Map<String, dynamic>.from(decoded);
  }

  int _readInt(dynamic value, int fallback) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  double _readDouble(dynamic value, double fallback) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  String _truncate(String value, int maxLength) {
    final clean = value.trim();
    if (clean.length <= maxLength) return clean;
    return '${clean.substring(0, maxLength)}…';
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
