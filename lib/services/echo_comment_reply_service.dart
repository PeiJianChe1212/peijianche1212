import 'package:http/http.dart' as http;

import '../ai/model_hub.dart';
import '../models/ai_character.dart';
import '../models/character_settings.dart';
import '../models/echo_item.dart';
import '../models/echo_comment.dart';
import 'api_settings_storage_service.dart';
import 'character_settings_storage_service.dart';
import 'character_registry_service.dart';
import 'character_relationship_context_service.dart';
import 'ai_social_protocol_service.dart';
import 'context_builder.dart';

class EchoCommentReplyService {
  EchoCommentReplyService({
    required this.character,
    http.Client? client,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null {
    _modelHub = ModelHub(client: _client);
  }

  final AiCharacter character;
  final http.Client _client;
  final bool _ownsClient;
  late final ModelHub _modelHub;

  final ApiSettingsStorageService _apiStorage = ApiSettingsStorageService();

  Future<String> generateReply({
    required EchoItem echo,
    EchoComment? userComment,
    EchoComment? targetComment,
    List<EchoComment> existingComments = const [],
  }) async {
    final comment = targetComment ?? userComment;
    if (comment == null) {
      throw ArgumentError('必须提供要回复的评论。');
    }
    final apiSettings = await _apiStorage.loadSettings();
    if (!apiSettings.isConfigured) {
      throw StateError('请先在“设置 → 模型与 API”中填写并保存接口配置。');
    }

    final settings = await CharacterSettingsStorageService(
      characterId: character.id,
    ).loadSettings();
    final allCharacters = await CharacterRegistryService().loadCharacters();
    final relationshipPrompt =
        await CharacterRelationshipContextService().buildPromptSection(
      currentCharacter: character,
      allCharacters: allCharacters,
    );

    final provider = await _modelHub.chatProvider();
    final raw = await provider.complete(
      messages: [
        {
          'role': 'system',
          'content': ContextBuilder.build(
            task: ContextTask.echoComment,
            settings: settings,
            taskRules: _buildSystemPrompt(settings),
            relationshipContext: relationshipPrompt,
            socialProtocol: AiSocialProtocolService.compactRules,
          ),
        },
        {
          'role': 'user',
          'content': '''
【${settings.characterName}发布的 Echo】
${echo.content}

【要回复的评论】
${comment.authorNameSnapshot}：${comment.content}

【评论区已有内容】
${existingComments.isEmpty ? '暂无其他评论' : existingComments.map((item) => '${item.authorNameSnapshot}：${item.content}').join('\n')}

请生成${settings.characterName}在评论区对这条评论的自然回复。
''',
        },
      ],
      temperature: settings.temperature.clamp(0.58, 0.82).toDouble(),
      maxTokens: 220,
      topP: 0.9,
    );

    final cleaned = _clean(raw);
    if (!_isValid(cleaned, target: comment, existing: existingComments)) {
      throw const FormatException('模型没有生成有效回复。');
    }
    return cleaned;
  }

  String _buildSystemPrompt(CharacterSettings settings) {
    return '''
你正在扮演${settings.characterName}，回复 PeiLink Echo 下的一条评论。

【评论区回复规则】
1. 只输出回复正文，不要标题、引号、解释、Markdown 或角色名前缀。
2. 这是评论区里的简短互动，不是重新开始一段聊天。
3. 回应对方评论的具体内容，不要答非所问。
4. 不使用括号动作、小说旁白或舞台指令。
5. 不要强行亲亲抱抱，不要套用“我会一直陪着你”等模板。
6. 不虚构 Echo 和评论中没有出现的具体事实。
7. 符合${settings.characterName}本人的语气，允许简短、接梗、吐槽或轻微情绪。
8. 即使评论提到其他角色，也不要争宠、挑衅、宣示唯一或逼用户表态。
9. 通常控制在 5 至 80 个汉字，最多两小段。
10. 自动回复到这里结束，不邀请其他角色继续对线，不制造新的争执。
''';
  }

  bool _isValid(
    String value, {
    required EchoComment target,
    required List<EchoComment> existing,
  }) {
    if (value.isEmpty || value.length > 100) return false;
    if (RegExp(r'[\(\（][^\)\）]*[\)\）]').hasMatch(value)) return false;
    if (_containsConflict(value)) return false;
    final normalized = _normalize(value);
    if (normalized == _normalize(target.content)) return false;
    return !existing.any((item) => _normalize(item.content) == normalized);
  }

  bool _containsConflict(String value) {
    return RegExp(
      r'只能是我的|只属于我|离她远点|离他远点|跟我抢|抢走她|抢走他|'
      r'你算什么|轮不到你|她是我的|他是我的|选我还是|二选一|'
      r'不许和.{0,8}(说话|见面|出去|联系)',
    ).hasMatch(value);
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'[，。！？、,.!?：:；;“”’\-—_]'), '');

  String _clean(String raw) {
    var value = raw.trim();
    value = value.replaceFirst(
      RegExp(r'^```(?:text|markdown)?\s*', caseSensitive: false),
      '',
    );
    value = value.replaceFirst(RegExp(r'\s*```$'), '');
    value = value.replaceFirst(RegExp(r'^(回复|评论回复)\s*[:：]\s*'), '');
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
