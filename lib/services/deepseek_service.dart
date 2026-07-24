import 'dart:convert';

import 'package:http/http.dart' as http;

import '../ai/model_hub.dart';
import '../conversation/conversation_engine.dart';
import '../models/chat_message.dart';
import '../models/pending_memory.dart';
import 'activity_context_service.dart';
import 'api_settings_storage_service.dart';
import 'character_settings_storage_service.dart';
import 'echo_chat_context_service.dart';
import 'memory_storage_service.dart';
import 'prompt_builder.dart';
import 'user_profile_storage_service.dart';

class DeepSeekService {
  DeepSeekService({http.Client? client}) : _client = client ?? http.Client() {
    _modelHub = ModelHub(client: _client);
  }

  final http.Client _client;
  late final ModelHub _modelHub;
  final UserProfileStorageService _profileStorage = UserProfileStorageService();
  final ApiSettingsStorageService _apiStorage = ApiSettingsStorageService();
  final MemoryStorageService _memoryStorage = MemoryStorageService();
  final CharacterSettingsStorageService _characterStorage =
      CharacterSettingsStorageService();

  Future<bool> get hasApiKey async =>
      (await _apiStorage.loadSettings()).isConfigured;

  void dispose() => _client.close();

  Future<String> sendMessage({
    required List<ChatMessage> messages,
    required String conversationMode,
    required double temperature,
    required String replyLength,
    required double initiative,
    required double intimacy,
    required double tsundere,
    String? characterId,
  }) async {
    final apiSettings = await _apiStorage.loadSettings();
    if (!apiSettings.isConfigured) {
      throw StateError('请先在“设置 → 模型与 API”中填写并保存接口配置。');
    }

    final validConversation = messages
        .where(
          (message) => message.role == 'user' || message.role == 'assistant',
        )
        .toList();
    final recentConversation = validConversation.length > 36
        ? validConversation.sublist(validConversation.length - 36)
        : validConversation;

    final userProfile = await _profileStorage.loadProfile();
    final memoryPrompt = await MemoryStorageService(
      characterId: characterId,
    ).buildPromptSection();
    final characterSettings = await CharacterSettingsStorageService(
      characterId: characterId,
    ).loadSettings();
    final activity = await ActivityContextService(
      characterId: characterId ?? 'default',
    ).resolve();
    final echoContextPrompt = characterId == null || characterId.trim().isEmpty
        ? ''
        : await EchoChatContextService(
            characterId: characterId,
          ).buildPromptSection();

    final conversationEngine = ConversationEngine.build(
      messages: validConversation,
      conversationMode: conversationMode,
    );

    final systemPrompt = '''
${PromptBuilder.buildSystemPrompt(
      characterSettings: characterSettings,
      userProfile: userProfile,
      timeContext: _buildTimeContext(),
      conversationEnginePrompt: conversationEngine.prompt,
      personalityPrompt: _buildPersonalityPrompt(
        initiative: initiative,
        intimacy: intimacy,
        tsundere: tsundere,
      ),
      replyLengthPrompt: _buildReplyLengthPrompt(replyLength),
      memoryPrompt: memoryPrompt,
      activityPrompt:
          validConversation.where((message) => message.role == 'user').length <= 1
          ? activity.toPromptSection()
          : '',
      styleExamplesPrompt: PromptBuilder.buildStyleExamplesPrompt(
        characterSettings,
      ),
    )}

$echoContextPrompt

【真实媒体规则】
你不能靠文字假装已经发送照片、图片、语音或视频。
除非聊天记录中真的存在一条由角色发送的 image 类型消息，否则禁止说“我拍了”“发给你了”“照片给你”“刚发过去”，也禁止用括号写“拍了一张发过去”“发送图片”。
当用户索要图片但系统尚未真正插入图片消息时，不要虚构已发送成功。
''';

    final requestMessages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': systemPrompt,
      },
      ...recentConversation.map<Map<String, dynamic>>(
        (message) => <String, dynamic>{
          'role': message.role,
          'content': _messageContentForModel(message),
        },
      ),
    ];

    final provider = await _modelHub.chatProvider();
    final content = await provider.complete(
      messages: requestMessages,
      temperature: temperature,
      maxTokens: _getMaxTokens(replyLength, conversationMode),
      topP: _getTopP(temperature),
    );
    return _cleanReply(content);
  }


  String _messageContentForModel(ChatMessage message) {
    if (message.type != MessageType.image) return message.content;

    final caption = message.content.trim();
    if (message.role == 'assistant') {
      final prompt =
          message.metadata['generationPrompt']?.toString().trim() ?? '';
      final parts = <String>['[角色刚刚发送了一张图片]'];
      if (prompt.isNotEmpty) parts.add('图片场景：$prompt');
      if (caption.isNotEmpty) parts.add('角色随图说：$caption');
      return parts.join('\n');
    }

    final description =
        message.metadata['visionDescription']?.toString().trim() ?? '';
    final parts = <String>['[用户发送了一张图片]'];
    if (description.isNotEmpty) {
      parts.add('图片内容：$description');
    } else {
      parts.add('图片内容暂时无法识别。不要假装看清了具体画面。');
    }
    if (caption.isNotEmpty) parts.add('用户随图片说：$caption');
    parts.add('请按照当前角色的说话方式自然回应图片和用户的话，不要复述识图报告。');
    return parts.join('\n');
  }

  Future<String> composeImageMessage({
    required String userRequest,
  }) async {
    final apiSettings = await _apiStorage.loadSettings();
    if (!apiSettings.isConfigured) {
      return '给你。';
    }

    final characterSettings = await _characterStorage.loadSettings();
    final provider = await _modelHub.chatProvider();
    final raw = await provider.complete(
      messages: [
        {
          'role': 'system',
          'content': '''
${characterSettings.toPromptSection()}

你刚刚按照用户的要求生成并发送了一张图片。
现在只写一句自然的随图消息，像聊天里把照片发过去时顺口说的话。
不要解释生成过程，不要说“AI绘图”“模型”“提示词”，不要复述完整画面描述。
通常 4 到 24 个字，最多两句。
''',
        },
        {'role': 'user', 'content': '用户原话：$userRequest'},
      ],
      temperature: 0.72,
      maxTokens: 80,
      topP: 0.86,
    );
    final cleaned = _cleanReply(raw)
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .trim();
    return cleaned.isEmpty ? '给你。' : cleaned;
  }

  Future<List<PendingMemory>> extractMemories({
    required List<ChatMessage> messages,
  }) async {
    final apiSettings = await _apiStorage.loadSettings();
    if (!apiSettings.isConfigured) {
      throw StateError('请先在“设置 → 模型与 API”中填写并保存接口配置。');
    }

    final conversation = messages
        .where(
          (message) => message.role == 'user' || message.role == 'assistant',
        )
        .toList();
    final recent = conversation.length > 24
        ? conversation.sublist(conversation.length - 24)
        : conversation;
    if (!recent.any((message) => message.role == 'user')) return [];

    final transcript = recent
        .map(
          (message) =>
              '${message.role == 'user' ? '林念念' : '裴简澈'}：${message.content}',
        )
        .join('\n');

    final provider = await _modelHub.chatProvider();
    final raw = await provider.complete(
      messages: [
        {
          'role': 'system',
          'content': '''
你是“裴简澈 OS”的记忆整理器。请只提取关于用户林念念的、长期有效且未来聊天确实有帮助的信息。

可以保存：长期兴趣、稳定偏好、害怕或禁忌、重要关系、长期习惯、重要经历、明确约定。
不要保存：当天吃了什么、天气、临时情绪、随口玩笑、尚未确认的猜测、裴简澈自己的台词、重复信息。

只返回 JSON 数组，不要 Markdown，不要解释。最多 5 条。
格式：
[{"content":"用户……","reason":"说明未来聊天为什么有用","category":"关于我/兴趣偏好/生活习惯/害怕与禁忌/重要关系/经历过的事/我们的约定/共同纪念"}]
没有值得保存的内容时返回 []。
''',
        },
        {'role': 'user', 'content': transcript},
      ],
      temperature: 0.15,
      maxTokens: 700,
    );
    return _parsePendingMemories(raw);
  }

  List<PendingMemory> _parsePendingMemories(String raw) {
    var cleaned = raw.trim();
    cleaned = cleaned.replaceFirst(
      RegExp(r'^```(?:json)?\s*', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceFirst(RegExp(r'\s*```$'), '');
    final start = cleaned.indexOf('[');
    final end = cleaned.lastIndexOf(']');
    if (start < 0 || end < start) return [];
    final decoded = jsonDecode(cleaned.substring(start, end + 1));
    if (decoded is! List) return [];
    const allowed = {
      '关于我',
      '兴趣偏好',
      '生活习惯',
      '害怕与禁忌',
      '重要关系',
      '经历过的事',
      '我们的约定',
      '共同纪念',
    };
    return decoded
        .whereType<Map>()
        .map((json) {
          final content = json['content']?.toString().trim() ?? '';
          final reason = json['reason']?.toString().trim() ?? '可能长期有效';
          final rawCategory = json['category']?.toString().trim() ?? '关于我';
          final normalizedCategory = rawCategory == '关于念念'
              ? '关于我'
              : rawCategory;
          return PendingMemory(
            content: content,
            reason: reason,
            category: allowed.contains(normalizedCategory)
                ? normalizedCategory
                : '关于我',
          );
        })
        .where((item) => item.content.isNotEmpty)
        .take(5)
        .toList();
  }

  String _buildTimeContext() {
    final now = DateTime.now();
    final weekDays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final weekDay = weekDays[now.weekday - 1];
    final timePeriod = switch (now.hour) {
      >= 5 && < 9 => '早上',
      >= 9 && < 12 => '上午',
      >= 12 && < 14 => '中午',
      >= 14 && < 18 => '下午',
      >= 18 && < 22 => '晚上',
      _ => '深夜',
    };
    final minute = now.minute.toString().padLeft(2, '0');
    return '''
【当前时间】

现在是${now.year}年${now.month}月${now.day}日，$weekDay，$timePeriod${now.hour}:$minute。

你知道当前日期和时间。

只有当话题与时间相关时，才自然提到时间。

不要每条回复都报时。

不要因为现在是深夜，就每句话都催林念念睡觉。
''';
  }

  String _buildPersonalityPrompt({
    required double initiative,
    required double intimacy,
    required double tsundere,
  }) {
    final initiativeRule = switch (initiative) {
      >= 0.72 => '主动程度较高：会自然追问具体细节、延续话题，偶尔主动提起与当前内容有关的新话题，但不要连续盘问。',
      >= 0.42 => '主动程度适中：先接住当前话题，在合适时追问一句或自然往下聊。',
      _ => '主动程度偏低：更多跟随林念念的节奏，不为了延续而强行提问。',
    };

    final intimacyRule = switch (intimacy) {
      >= 0.72 => '亲密表达较明显：可以更自然地表达想念、在意和恋人间的偏爱，但普通话题仍以事情本身为主，禁止句句亲亲抱抱。',
      >= 0.42 => '亲密表达适中：亲近感藏在语气、观察和回应里，不刻意制造情话。',
      _ => '亲密表达克制：更含蓄地表现关心，减少直白爱意和身体接触类表达。',
    };

    final tsundereRule = switch (tsundere) {
      >= 0.72 => '嘴硬程度较高：可以多用轻微反问、酸一下、故意曲解和嘴硬掩饰在意，但不能刻薄、威胁或控制。',
      >= 0.42 => '嘴硬程度适中：偶尔嘴硬、接梗或吃一点醋，真正需要安慰时会收起来。',
      _ => '嘴硬程度较低：表达更坦率直接，少用反话和故意逗弄。',
    };

    return '''
【当前人格调节】

$initiativeRule

$intimacyRule

$tsundereRule

这些调节只改变表达倾向，不能覆盖裴简澈的核心人格、边界和禁止事项。
''';
  }

  double _getTopP(double temperature) {
    return (0.78 + (temperature - 0.55) * 0.28).clamp(0.78, 0.88).toDouble();
  }

  String _buildReplyLengthPrompt(String replyLength) {
    return switch (replyLength) {
      'short' => '回复尽量简短，通常1到2句，避免无必要展开。',
      'long' => '回复可以偏长，通常3到6句，但保持自然，不写成文章。',
      _ => '回复长度适中，通常1到4句，根据话题自然调整。',
    };
  }

  int _getMaxTokens(String replyLength, String conversationMode) {
    var maxTokens = switch (replyLength) {
      'short' => 180,
      'long' => 520,
      _ => 300,
    };
    if (conversationMode == 'long' && maxTokens < 480) maxTokens = 480;
    if (conversationMode == 'deep' && maxTokens < 520) maxTokens = 520;
    return maxTokens;
  }

  String _cleanReply(String reply) {
    var cleaned = reply.trim();
    for (final prefix in ['裴简澈：', '裴简澈:', '助手：', '助手:']) {
      if (cleaned.startsWith(prefix)) {
        cleaned = cleaned.substring(prefix.length).trim();
      }
    }
    if (cleaned.length >= 2 &&
        cleaned.startsWith('“') &&
        cleaned.endsWith('”')) {
      cleaned = cleaned.substring(1, cleaned.length - 1);
    }
    return cleaned.trim();
  }
}
