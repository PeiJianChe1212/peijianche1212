import 'package:http/http.dart' as http;

import '../ai/model_hub.dart';
import '../models/ai_character.dart';
import '../models/chat_message.dart';
import '../models/character_settings.dart';
import '../models/memory_item.dart';
import 'api_settings_storage_service.dart';
import 'character_settings_storage_service.dart';
import 'chat_storage_service.dart';
import 'memory_storage_service.dart';

class EchoGenerationService {
  EchoGenerationService({
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

  Future<String> generateDraft() async {
    final apiSettings = await _apiStorage.loadSettings();
    if (!apiSettings.isConfigured) {
      throw StateError('请先在“设置 → 模型与 API”中填写并保存接口配置。');
    }

    final characterId = character.id;
    final settings = await CharacterSettingsStorageService(
      characterId: characterId,
    ).loadSettings();
    final messages = await ChatStorageService(
      characterId: characterId,
    ).loadMessages();
    final memories = await MemoryStorageService(
      characterId: characterId,
    ).loadItems();

    final provider = await _modelHub.chatProvider();
    final raw = await provider.complete(
      messages: [
        {
          'role': 'system',
          'content': _buildSystemPrompt(
            settings: settings,
            messages: messages,
            memories: memories,
          ),
        },
        {
          'role': 'user',
          'content': '请以${settings.characterName}本人的口吻，生成一条现在适合发布在 Echo 的生活动态草稿。',
        },
      ],
      temperature: settings.temperature.clamp(0.62, 0.86).toDouble(),
      maxTokens: 420,
      topP: 0.9,
    );

    final cleaned = _clean(raw);
    if (cleaned.isEmpty) {
      throw const FormatException('模型没有生成有效的 Echo 内容。');
    }
    return cleaned;
  }

  String _buildSystemPrompt({
    required CharacterSettings settings,
    required List<ChatMessage> messages,
    required List<MemoryItem> memories,
  }) {
    final now = DateTime.now();
    final weekDays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final recentMessages = messages
        .where((item) => item.role == 'user' || item.role == 'assistant')
        .toList();
    final selectedMessages = recentMessages.length > 24
        ? recentMessages.sublist(recentMessages.length - 24)
        : recentMessages;
    final selectedMemories = memories
        .where((item) => !item.isArchived && item.category != '收藏回复')
        .take(20)
        .toList();

    final conversationText = selectedMessages.isEmpty
        ? '暂无可参考的近期聊天。'
        : selectedMessages
              .map((item) {
                final speaker = item.role == 'user'
                    ? settings.userCallName
                    : settings.characterName;
                return '$speaker：${_truncate(item.content.trim(), 280)}';
              })
              .join('\n');

    final memoryText = selectedMemories.isEmpty
        ? '暂无已确认记忆。'
        : selectedMemories
              .map((item) => '- ${_truncate(item.content.trim(), 220)}')
              .join('\n');

    return '''
你正在为 PeiLink 的 Echo 生成一条角色生活动态。

【角色身份】
${settings.coreProfile}

【角色表达方式】
${settings.behaviorStyle}

【角色禁用规则】
${settings.forbiddenRules}

【当前时间】
${now.year}年${now.month}月${now.day}日，${weekDays[now.weekday - 1]}，${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}。

【近期聊天】
$conversationText

【已确认 Memory】
$memoryText

【Echo 的定位】
Echo 不是聊天回复，也不是给用户写的情书。
它是${settings.characterName}自己的生活主页，用来记录本人此刻的观察、工作、琐事、兴趣、吐槽、偶发情绪或生活片段。
可以偶尔自然提到${settings.userCallName}，但不能每条都围着对方转。

【生成规则】
1. 只输出动态正文，不要标题、引号、标签、解释或 Markdown。
2. 不要称呼用户后继续聊天，不要提问，不要邀请用户回复。
3. 不要写“我会一直陪着你”“宝宝辛苦了”等陪伴模板。
4. 不使用括号动作、小说旁白、舞台指令或心理活动标注。
5. 不虚构具体天气、新闻、地点、节日或已经发生但资料中没有依据的事件。
6. 可以从近期聊天和 Memory 获得灵感，但不要逐字复述聊天，也不要泄露“我读取了记忆”。
7. 内容应符合当前角色，像本人随手发出的生活记录。
8. 控制在 20 至 180 个汉字，一到三小段；允许简短，但不要长篇总结。
9. 不必煽情，不必每次浪漫，不必每次提关系。
10. 如果资料不足，就生成不依赖外部事实的普通生活观察或个人想法。
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

  String _truncate(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    return '${value.substring(0, maxLength)}…';
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
