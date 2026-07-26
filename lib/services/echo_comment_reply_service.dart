import 'package:http/http.dart' as http;

import '../ai/model_hub.dart';
import '../models/ai_character.dart';
import '../models/character_settings.dart';
import '../models/echo_item.dart';
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
    required EchoComment userComment,
  }) async {
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

【${settings.userCallName}的评论】
${userComment.content}

请生成${settings.characterName}在评论区对这条评论的自然回复。
''',
        },
      ],
      temperature: settings.temperature.clamp(0.58, 0.82).toDouble(),
      maxTokens: 220,
      topP: 0.9,
    );

    final cleaned = _clean(raw);
    if (cleaned.isEmpty) {
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
''';
  }

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
