import 'package:http/http.dart' as http;

import '../ai/model_hub.dart';
import '../models/activity_status.dart';
import '../models/chat_message.dart';
import '../models/character_settings.dart';
import '../models/character_user_profile.dart';
import '../conversation/conversation_engine.dart';
import '../conversation/chat_reply_sanitizer.dart';
import '../context_builder/context_build_result.dart';
import '../prompt_composer/prompt_composer.dart';
import '../prompt_composer/prompt_context.dart';
import 'character_user_profile_storage_service.dart';
import 'context_builder.dart';
import 'memory2_chat_context_builder.dart';
import 'memory_storage_service.dart';
import 'user_profile_storage_service.dart';

class ProactiveMessageGenerationResult {
  const ProactiveMessageGenerationResult({
    required this.content,
    required this.usedModel,
    required this.usedFallback,
    required this.usedLifeEvent,
  });

  final String content;
  final bool usedModel;
  final bool usedFallback;
  final bool usedLifeEvent;
}

/// 只负责生成主动联系内容，不负责次数、时间窗口或冷却判断。
class ProactiveMessageGenerationService {
  ProactiveMessageGenerationService({
    required this.characterId,
    http.Client? client,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null {
    _modelHub = ModelHub(client: _client);
  }

  final String characterId;
  final http.Client _client;
  final bool _ownsClient;
  late final ModelHub _modelHub;

  Future<ProactiveMessageGenerationResult> generate({
    required CharacterSettings settings,
    required ActivityStatus activity,
    required DateTime now,
    required String slot,
    required List<ChatMessage> messages,
    required List<String> recentProactiveMessages,
    required String fallbackMessage,
    String lifeEventSummary = '',
  }) async {
    final usedLifeEvent = lifeEventSummary.trim().isNotEmpty;

    try {
      final userProfile = await UserProfileStorageService().loadProfile();
      final characterUserProfile = await _loadCharacterUserProfile();
      final memory = await _compactMemory();
      final provider = await _modelHub.chatProvider();
      final conversationEngine = ConversationEngine.build(
        messages: messages,
        conversationMode: 'basic',
      );
      final prompt = ContextBuilder.build(
        task: ContextTask.proactiveChat,
        settings: settings,
        userProfile: userProfile,
        taskRules: _taskRules(settings),
        dynamicState: _dynamicState(
          activity: activity,
          now: now,
          slot: slot,
          lastUserAt: _lastUserMessageAt(messages),
        ),
        relevantMemory: memory,
        recentConversation: _recentConversation(messages),
        sourceFacts: _sourceFacts(
          lifeEventSummary: lifeEventSummary,
          recentProactiveMessages: recentProactiveMessages,
        ),
        now: now,
      );

      for (var attempt = 0; attempt < 2; attempt++) {
        final userInstruction = attempt == 0
            ? '生成一条此刻自然发给用户的主动消息，只输出正文。'
            : '上一条不合格。重新生成一条更短、更自然、且不重复近期内容的消息，只输出正文。';
        final modelContext =
            PromptComposer(
                  baseContext: ContextBuildResult(
                    messages: [
                      {'role': 'system', 'content': prompt},
                      {'role': 'user', 'content': userInstruction},
                    ],
                    systemPrompt: prompt,
                  ),
                )
                .addContext(
                  PromptContext.extension(
                    id: 'character_user_profile',
                    content: Memory2ChatContextBuilder
                        .characterUserProfileSection(characterUserProfile),
                    priority: PromptContextPriority.memory,
                  ),
                )
                .addContext(PromptContext.chatFlow(conversationEngine.prompt))
                .compose();
        final raw = await provider.complete(
          messages: modelContext.messages,
          temperature: settings.temperature.clamp(0.58, 0.78).toDouble(),
          maxTokens: 100,
          topP: 0.88,
        );
        final cleaned = _clean(raw);
        if (_isValid(
          cleaned,
          recentProactiveMessages: recentProactiveMessages,
          lifeEventSummary: lifeEventSummary,
        )) {
          return ProactiveMessageGenerationResult(
            content: cleaned,
            usedModel: true,
            usedFallback: false,
            usedLifeEvent: usedLifeEvent,
          );
        }
      }
    } catch (error) {
      // 主动联系不能因为模型失败中断，交由旧固定消息兜底。
      // ignore: avoid_print
      print('[Initiative][$characterId] model generation failed: $error');
    }

    return ProactiveMessageGenerationResult(
      content: fallbackMessage,
      usedModel: false,
      usedFallback: true,
      usedLifeEvent: false,
    );
  }

  Future<String> _compactMemory() async {
    final items = await MemoryStorageService(
      characterId: characterId,
    ).loadItems();
    final usable = items.where((item) => !item.isArchived).toList()
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });
    if (usable.isEmpty) return '';
    return usable.take(5).map((item) => '- ${item.content.trim()}').join('\n');
  }

  Future<CharacterUserProfile> _loadCharacterUserProfile() async {
    try {
      return await CharacterUserProfileStorageService(
        characterId: characterId,
      ).load();
    } catch (_) {
      return CharacterUserProfile(characterId: characterId);
    }
  }

  String _taskRules(CharacterSettings settings) =>
      '''
你正在以${settings.characterName}的身份，主动给用户发一条私人聊天消息。
1. 只生成一条消息，以 1 至 2 句话为主，建议 8 至 55 个汉字。
2. 语气必须符合角色本人，像自然想到用户后发来的话，不像通知、客服或定时问候。
3. 可以结合当前状态、最近聊天和最近生活，但不要把所有信息都塞进去。
4. 禁止用（）、()、[]、【】或 *动作* 输出独立动作、心理或舞台标签，也不写小说旁白、标题、编号、Markdown、JSON、代码或系统说明。状态或行为只能自然融进消息正文。
5. 不要自动替用户回答，不开启完整剧情，不连续抛出多个问题。
6. 禁止“在吗”“怎么不理我”“为什么不回我”等催促，也不要高频亲密动作。
7. 不直接复制 Echo 或生活事件原句。公开动态与私人联系应使用不同表达。
8. 不虚构本次上下文没有提供的事实。
9. 只输出最终消息正文。
''';

  String _dynamicState({
    required ActivityStatus activity,
    required DateTime now,
    required String slot,
    required DateTime? lastUserAt,
  }) {
    return '''
主动消息触发时段：$slot
当前活动：${activity.label}
活动说明：${activity.detail}
用户最后发言时间：${lastUserAt?.toIso8601String() ?? '暂无记录'}
''';
  }

  String _recentConversation(List<ChatMessage> messages) {
    final selected = messages
        .where((item) => item.type == MessageType.text)
        .toList()
        .reversed
        .take(8)
        .toList()
        .reversed;
    if (selected.isEmpty) return '';
    return selected
        .map((item) {
          final speaker = item.role == 'user' ? '用户' : '角色';
          return '$speaker：${_shorten(item.content, 90)}';
        })
        .join('\n');
  }

  String _sourceFacts({
    required String lifeEventSummary,
    required List<String> recentProactiveMessages,
  }) {
    final sections = <String>[];
    if (lifeEventSummary.trim().isNotEmpty) {
      sections.add('最近真实生活片段：${lifeEventSummary.trim()}');
    }
    if (recentProactiveMessages.isNotEmpty) {
      sections.add(
        '近期已经主动发送过的内容，禁止复用：\n${recentProactiveMessages.take(5).map((item) => '- $item').join('\n')}',
      );
    }
    return sections.join('\n\n');
  }

  DateTime? _lastUserMessageAt(List<ChatMessage> messages) {
    for (final item in messages.reversed) {
      if (item.role == 'user') return item.createdAt;
    }
    return null;
  }

  bool _isValid(
    String value, {
    required List<String> recentProactiveMessages,
    required String lifeEventSummary,
  }) {
    final clean = value.trim();
    if (clean.isEmpty || clean.length > 80) return false;
    if (RegExp(
      r'```|\{\s*"|system\s*prompt|系统提示|^\s*\d+[\.、]',
    ).hasMatch(clean)) {
      return false;
    }
    if (RegExp(r'在吗|怎么不理我|为什么不回我|忙吗[？?]?$').hasMatch(clean)) {
      return false;
    }
    if (clean.split('\n').where((line) => line.trim().isNotEmpty).length > 2) {
      return false;
    }
    for (final previous in recentProactiveMessages) {
      if (_similar(clean, previous)) return false;
    }
    final life = lifeEventSummary.trim();
    if (life.isNotEmpty && clean == life) return false;
    return true;
  }

  bool _similar(String first, String second) {
    final a = _normalize(first);
    final b = _normalize(second);
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b || a.contains(b) || b.contains(a)) return true;
    final chars = a.split('').toSet();
    final other = b.split('').toSet();
    final union = chars.union(other).length;
    if (union == 0) return false;
    return chars.intersection(other).length / union >= 0.72;
  }

  String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r"[\s，。！？、,.!?~～“”'（）()…]"), '');

  String _clean(String value) {
    var clean = value.trim();
    clean = clean.replaceAll(RegExp(r'^```(?:text)?\s*'), '');
    clean = clean.replaceAll(RegExp(r'\s*```$'), '');
    clean = clean.replaceAll(RegExp(r'^["“]|["”]$'), '');
    clean = clean.replaceAll(RegExp(r'^(消息|正文|回复)[:：]\s*'), '');
    return ChatReplySanitizer.clean(clean);
  }

  String _shorten(String value, int maxLength) {
    final clean = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.length <= maxLength) return clean;
    return '${clean.substring(0, maxLength).trim()}…';
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
