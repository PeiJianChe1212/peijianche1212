import 'package:http/http.dart' as http;

import '../ai/model_hub.dart';
import '../models/ai_character.dart';
import '../models/character_relationship.dart';
import '../models/echo_comment.dart';
import '../models/echo_item.dart';
import 'ai_social_protocol_service.dart';
import 'api_settings_storage_service.dart';
import 'character_settings_storage_service.dart';
import 'context_builder.dart';
import 'echo_comment_diversity_service.dart';

class EchoCommentGenerationService {
  EchoCommentGenerationService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null {
    _modelHub = ModelHub(client: _client);
  }

  final http.Client _client;
  final bool _ownsClient;
  late final ModelHub _modelHub;
  final ApiSettingsStorageService _apiStorage = ApiSettingsStorageService();
  final EchoCommentDiversityService _diversity =
      const EchoCommentDiversityService();

  Future<String> generate({
    required AiCharacter commenter,
    required String authorName,
    required EchoItem echo,
    required List<EchoComment> existingComments,
    CharacterRelationship? relationship,
    String triggerReason = '',
    String contentType = 'daily',
    String activityLabel = '',
    String styleHint = '',
  }) async {
    final apiSettings = await _apiStorage.loadSettings();
    if (!apiSettings.isConfigured) {
      throw StateError('API 尚未配置。');
    }

    final settings = await CharacterSettingsStorageService(
      characterId: commenter.id,
    ).loadSettings();
    final recentByCommenter = existingComments
        .where((item) => item.authorId == commenter.id)
        .toList()
        .reversed
        .take(3)
        .map((item) => item.content)
        .join('\n');
    final relationshipText = relationship == null
        ? 'Echo 发布者是用户本人。按你与用户既有关系自然回应。'
        : '''
你与发布者的关系阶段：${relationship.stage.label}
共同经历次数：${relationship.sharedEventCount}
关系备注：${relationship.note.trim().isEmpty ? '无' : relationship.note.trim()}
''';

    final provider = await _modelHub.chatProvider();
    final raw = await provider.complete(
      messages: [
        {
          'role': 'system',
          'content': ContextBuilder.build(
            task: ContextTask.echoComment,
            settings: settings,
            taskRules: _rules(commenter.characterName),
            relationshipContext: relationshipText,
            socialProtocol: AiSocialProtocolService.compactRules,
            recentConversation: recentByCommenter.isEmpty
                ? ''
                : '你近期在 Echo 留过的评论：\n$recentByCommenter',
            dynamicState:
                activityLabel.isEmpty ? '' : '当前活动：$activityLabel',
            sourceFacts: '''
发布者：$authorName
Echo 正文：${echo.content}
Echo 类型：$contentType
本次允许评论的原因：${triggerReason.isEmpty ? '与当前关系和内容相关' : triggerReason}
生活事件 ID：${echo.sourceLifeEventId.trim().isEmpty ? '未记录' : echo.sourceLifeEventId}
当前已有评论：
${existingComments.isEmpty ? '暂无' : existingComments.map((item) => '${item.authorNameSnapshot}：${item.content}').join('\n')}
${styleHint.trim()}
''',
          ),
        },
        {
          'role': 'user',
          'content': '判断自己确实有话可说后，写一条自然的 Echo 评论。只输出评论正文。',
        },
      ],
      temperature: settings.temperature.clamp(0.58, 0.78).toDouble(),
      maxTokens: 100,
      topP: 0.88,
    );

    final cleaned = _clean(raw);
    if (!_isValid(cleaned, echo: echo, existing: existingComments)) {
      throw const FormatException('模型评论未通过内容校验。');
    }
    return cleaned;
  }

  String _rules(String characterName) => '''
你是$characterName，正在 PeiLink 的 Echo 评论区留下一条公开评论。
1. 通常一句，5 至 50 个汉字；只有确实需要时才写两句。
2. 回应 Echo 里的具体内容，不能增加 Echo 没有提供的新事实。
3. 保持你自己的说话方式；可以平淡、简短或轻微调侃，不必总是夸赞。
4. 不写括号动作、小说旁白、角色名前缀、标题、引号或 Markdown。
5. 不把评论写成聊天剧情，不长篇分析，不替发布者解释内心，不反复提问。
6. 不争宠、不吃醋对线、不宣示唯一占有、不否定其他角色与用户的关系。
7. 不重复已有评论，也不照抄 Echo 原文。
8. 只输出评论正文。
''';

  bool _isValid(
    String value, {
    required EchoItem echo,
    required List<EchoComment> existing,
  }) {
    if (value.isEmpty || value.length > 80) return false;
    if (RegExp(r'[\(\（][^\)\）]*[\)\）]').hasMatch(value)) return false;
    if (_containsConflict(value)) return false;
    final normalized = _normalize(value);
    if (normalized.isEmpty || normalized == _normalize(echo.content)) {
      return false;
    }
    return !existing.any(
      (item) => _diversity.isSemanticallySimilar(item.content, value),
    );
  }

  bool _containsConflict(String value) {
    return RegExp(
      r'只能是我的|只属于我|离她远点|离他远点|跟我抢|抢走她|抢走他|'
      r'你算什么|轮不到你|她是我的|他是我的|选我还是|二选一|'
      r'不许和.{0,8}(说话|见面|出去|联系)|宣示主权',
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
    value = value.replaceFirst(RegExp(r'^(评论|正文)\s*[:：]\s*'), '');
    if (value.length > 1 &&
        ((value.startsWith('“') && value.endsWith('”')) ||
            (value.startsWith('"') && value.endsWith('"')))) {
      value = value.substring(1, value.length - 1).trim();
    }
    return value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
