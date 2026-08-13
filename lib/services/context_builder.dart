import '../models/character_settings.dart';
import '../models/character_archive.dart';
import '../models/character_profile.dart';
import '../models/user_profile.dart';
import '../prompts/relationship_prompt.dart';
import '../context_builder/character_context.dart';
import '../context_builder/character_archive_context_builder.dart';
import '../context_builder/context_build_result.dart';
import '../context_builder/conversation_context.dart';
import '../context_builder/memory_context.dart';
import '../context_builder/relationship_context.dart';
import '../context_builder/response_strategy_context.dart';
import '../models/chat_message.dart';

enum ContextTask {
  chat,
  echo,
  echoComment,
  image,
  imageMessage,
  lifeDecision,
  lifeGeneration,
  momentSelection,
  relationshipAnalysis,
  memoryExtraction,
  summary,
  multimodal,
  imageRouting,
  proactiveChat,
  groupChat,
}

enum ContextProfile {
  chat,
  echo,
  image,
  life,
  relationship,
  memory,
  summary,
  multimodal,
}

/// PeiLink 所有模型任务的人设上下文唯一拼装入口。
///
/// 业务层只提供本次任务的规则与事实，不再直接拼装角色核心设定。
class ContextBuilder {
  const ContextBuilder._();

  static final Map<String, String> _stableCache = <String, String>{};

  static ContextProfile profileFor(ContextTask task) {
    return switch (task) {
      ContextTask.chat ||
      ContextTask.imageMessage ||
      ContextTask.proactiveChat ||
      ContextTask.groupChat => ContextProfile.chat,
      ContextTask.echo || ContextTask.echoComment => ContextProfile.echo,
      ContextTask.image || ContextTask.imageRouting => ContextProfile.image,
      ContextTask.lifeDecision ||
      ContextTask.lifeGeneration ||
      ContextTask.momentSelection => ContextProfile.life,
      ContextTask.relationshipAnalysis => ContextProfile.relationship,
      ContextTask.memoryExtraction => ContextProfile.memory,
      ContextTask.summary => ContextProfile.summary,
      ContextTask.multimodal => ContextProfile.multimodal,
    };
  }

  static String build({
    required ContextTask task,
    required CharacterSettings settings,
    UserProfile? userProfile,
    String taskRules = '',
    String dynamicState = '',
    String relevantMemory = '',
    String recentConversation = '',
    String extensionProfile = '',
    String relationshipContext = '',
    String socialProtocol = '',
    String styleExamples = '',
    String sourceFacts = '',
    CharacterProfile? characterProfile,
    CharacterArchive? characterArchive,
  }) {
    final profile = profileFor(task);
    final sections = <String>[
      _stableContext(
        profile: profile,
        settings: settings,
        userProfile: userProfile,
        extensionProfile: extensionProfile,
        styleExamples: styleExamples,
        characterProfile: characterProfile,
        characterArchive: characterArchive,
      ),
    ];

    _add(sections, '任务规则', taskRules);
    _add(sections, '当前动态状态', dynamicState);
    _add(sections, '本次任务相关记忆', relevantMemory);
    _add(sections, '最近真实互动', recentConversation);
    _add(sections, '关系上下文', relationshipContext);
    _add(sections, '多角色共存规则', socialProtocol);
    _add(sections, '本次任务唯一事实来源', sourceFacts);

    return sections
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join('\n\n');
  }

  static void clearCache() => _stableCache.clear();

  /// 单聊模型请求的统一入口。
  ///
  /// 保持 v1 的 Prompt 内容与顺序，只把原先散落的拼接收口到五层上下文。
  static ContextBuildResult buildChatRequest({
    required CharacterContext character,
    required RelationshipContext relationship,
    required MemoryContext memory,
    required ConversationContext conversation,
    required ResponseStrategyContext responseStrategy,
    required String Function(ChatMessage message) messageContent,
  }) {
    final stablePrompt = build(
      task: ContextTask.chat,
      settings: character.settings,
      userProfile: character.userProfile,
      styleExamples: character.styleExamples,
      characterProfile: character.profile,
      characterArchive: character.archive,
    );
    final latestUserMessage = conversation.recentMessages
        .where((message) => message.role == 'user')
        .map(messageContent)
        .lastOrNull;
    final archivePrompt = character.archive == null
        ? ''
        : const CharacterArchiveContextBuilder().build(
            archive: character.archive!,
            latestUserMessage: latestUserMessage ?? '',
          );
    final relevantProfilePrompt = _relevantProfileContext(
      character.profile,
      latestUserMessage ?? '',
    );
    final relationshipPrompt = relationship.buildPromptSection();
    final dynamicSections = <String>[
      responseStrategy.dynamicPrompt,
      relevantProfilePrompt,
      archivePrompt,
      relationshipPrompt,
      responseStrategy.mediaRules,
    ].where((value) => value.trim().isNotEmpty).join('\n\n');
    final systemPrompt = '$stablePrompt\n\n$dynamicSections';
    final requestMessages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
      ...conversation.recentMessages.map<Map<String, dynamic>>(
        (message) => <String, dynamic>{
          'role': message.role,
          'content': messageContent(message),
        },
      ),
    ];

    // 不输出 Prompt 正文，避免角色设定和用户记忆进入日志。
    // ignore: avoid_print
    print(
      '[ContextBuilder] chat request built: '
      'character=${character.settings.characterName}, '
      'memory=${memory.confirmedMemory.trim().isNotEmpty}, '
      'conversationMessages=${conversation.recentMessages.length}',
    );
    return ContextBuildResult(
      messages: requestMessages,
      systemPrompt: systemPrompt,
    );
  }

  static String _stableContext({
    required ContextProfile profile,
    required CharacterSettings settings,
    required UserProfile? userProfile,
    required String extensionProfile,
    required String styleExamples,
    CharacterProfile? characterProfile,
    CharacterArchive? characterArchive,
  }) {
    final key = <Object?>[
      profile.name,
      settings.characterName,
      settings.remark,
      settings.relation,
      settings.userCallName,
      settings.coreProfile,
      settings.behaviorStyle,
      settings.forbiddenRules,
      settings.introduction,
      userProfile?.toJson().toString() ?? '',
      extensionProfile,
      styleExamples,
      characterProfile?.toJson().toString() ?? '',
      _fixedArchiveBehavior(characterArchive),
    ].join('|');

    return _stableCache.putIfAbsent(key, () {
      final sections = <String>[
        _coreIdentity(settings, characterProfile),
        _appearance(settings, characterProfile),
        _personality(characterProfile),
        _backgroundStory(characterProfile),
        _relationshipProfile(characterProfile),
      ];

      if (_usesUserProfile(profile) && userProfile != null) {
        sections.add(userProfile.toPromptSection());
      }
      if (_usesRelationshipBase(profile)) sections.add(relationshipPrompt);
      if (_usesBehavior(profile)) {
        sections.add(_behaviorRules(settings, characterArchive));
      }
      if (_usesAppearance(profile)) {
        final extension = extensionProfile.trim().isEmpty
            ? settings.introduction.trim()
            : extensionProfile.trim();
        if (extension.isNotEmpty) {
          sections.add('【外貌与扩展设定｜按需加载】\n$extension');
        }
      }
      if (styleExamples.trim().isNotEmpty && profile == ContextProfile.chat) {
        sections.add(styleExamples.trim());
      }

      return sections.join('\n\n').trim();
    });
  }

  static String _coreIdentity(
    CharacterSettings settings,
    CharacterProfile? profile,
  ) {
    String prefer(String current, String fallback) =>
        current.trim().isNotEmpty ? current.trim() : fallback.trim();
    final name = prefer(profile?.name ?? '', settings.characterName);
    final lines = <String>[
      _labeled('角色本名', name),
      _labeled('核心人设', settings.coreProfile),
    ].where((value) => value.isNotEmpty).join('\n');
    return _limit('【核心角色资料｜必读】\n$lines', 650);
  }

  static String _appearance(
    CharacterSettings settings,
    CharacterProfile? profile,
  ) {
    final overallAppearance = profile?.overallAppearance.trim() ?? '';
    final lines = <String>[
      _labeled(
        '整体外貌',
        overallAppearance.isNotEmpty
            ? overallAppearance
            : settings.introduction,
      ),
      _labeled('穿着', profile?.clothingStyle ?? ''),
    ].where((value) => value.isNotEmpty).join('\n');
    return lines.isEmpty ? '' : _limit('【外貌设定｜存在时读取】\n$lines', 500);
  }

  static String _personality(CharacterProfile? profile) {
    final description = profile?.personalityDescription.trim() ?? '';
    final lines = <String>[
      _labeled('性格描述', description),
      _labeled('性格标签', profile?.personalityTags ?? ''),
      _labeled('说话风格', profile?.speakingStyle ?? ''),
    ].where((value) => value.isNotEmpty).join('\n');
    return lines.isEmpty ? '' : _limit('【性格设定｜存在时读取】\n$lines', 350);
  }

  static String _relationshipProfile(CharacterProfile? profile) {
    if (profile == null) return '';
    final lines = <String>[
      _labeled('角色关系', profile.characterRelationships),
      _labeled('兴趣爱好', profile.interests),
      _labeled('讨厌的事', profile.dislikes),
      _labeled('持有物品', profile.possessions),
      _labeled('特殊能力', profile.specialAbilities),
    ].where((value) => value.isNotEmpty).join('\n');
    return lines.isEmpty ? '' : _limit('【关系资料｜存在时读取】\n$lines', 450);
  }

  static String _backgroundStory(CharacterProfile? profile) {
    if (profile == null) return '';
    final lines = <String>[
      _labeled('背景经历', profile.backgroundStory),
      _labeled('世界观', profile.worldview),
    ].where((value) => value.isNotEmpty).join('\n');
    return lines.isEmpty ? '' : _limit('【背景经历｜必读】\n$lines', 1000);
  }

  static String _behaviorRules(
    CharacterSettings settings,
    CharacterArchive? archive,
  ) =>
      '''
【行为规则｜按任务加载】
${settings.behaviorStyle}
${_fixedArchiveBehavior(archive)}

【禁止事项】
${settings.forbiddenRules}
''';

  static String _fixedArchiveBehavior(CharacterArchive? archive) {
    if (archive == null) return '';
    final values = <String>[
      _labeled('语言习惯', archive.value('languageHabits')),
      _labeled('回复风格', archive.value('speakingStyle')),
      _labeled('聊天节奏', archive.value('chatPace')),
      _labeled('表达特点', archive.value('expressionTraits')),
    ].where((value) => value.isNotEmpty).join('\n');
    return _limit(values, 500);
  }

  static String _relevantProfileContext(
    CharacterProfile? profile,
    String latestUserMessage,
  ) {
    if (profile == null) return '';
    final asksAboutPast = const [
      '小时候',
      '童年',
      '少年',
      '长大',
      '成长',
      '经历',
      '过去',
      '转折',
    ].any(latestUserMessage.contains);
    if (!asksAboutPast) return '';
    final facts = <String>[
      _labeled('家庭背景', profile.familyBackground),
      _labeled('成长经历', profile.upbringing),
      _labeled('重要经历', profile.importantExperiences),
      _labeled('世界观', profile.worldview),
    ].where((value) => value.isNotEmpty).join('\n');
    return facts.isEmpty ? '' : _limit('【背景故事｜按需加载】\n$facts', 800);
  }

  static String _labeled(String label, String value) {
    final clean = value.trim();
    return clean.isEmpty ? '' : '$label：$clean';
  }

  static String _limit(String value, int maxCharacters) {
    final clean = value.trim();
    if (clean.length <= maxCharacters) return clean;
    return '${clean.substring(0, maxCharacters - 1).trimRight()}…';
  }

  static bool _usesUserProfile(ContextProfile profile) =>
      profile == ContextProfile.chat ||
      profile == ContextProfile.relationship ||
      profile == ContextProfile.memory;

  static bool _usesRelationshipBase(ContextProfile profile) =>
      profile == ContextProfile.chat || profile == ContextProfile.relationship;

  static bool _usesBehavior(ContextProfile profile) =>
      profile != ContextProfile.image && profile != ContextProfile.multimodal;

  static bool _usesAppearance(ContextProfile profile) =>
      profile == ContextProfile.image ||
      profile == ContextProfile.multimodal ||
      profile == ContextProfile.life;

  static void _add(List<String> sections, String title, String value) {
    final clean = value.trim();
    if (clean.isNotEmpty) sections.add('【$title】\n$clean');
  }
}
