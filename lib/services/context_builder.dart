import '../models/character_settings.dart';
import '../models/user_profile.dart';
import '../prompts/relationship_prompt.dart';

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
      ContextTask.chat || ContextTask.imageMessage => ContextProfile.chat,
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
  }) {
    final profile = profileFor(task);
    final sections = <String>[
      _stableContext(
        profile: profile,
        settings: settings,
        userProfile: userProfile,
        extensionProfile: extensionProfile,
        styleExamples: styleExamples,
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

  static String _stableContext({
    required ContextProfile profile,
    required CharacterSettings settings,
    required UserProfile? userProfile,
    required String extensionProfile,
    required String styleExamples,
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
    ].join('|');

    return _stableCache.putIfAbsent(key, () {
      final sections = <String>[_coreIdentity(settings)];

      if (_usesUserProfile(profile) && userProfile != null) {
        sections.add(userProfile.toPromptSection());
      }
      if (_usesRelationshipBase(profile)) sections.add(relationshipPrompt);
      if (_usesBehavior(profile)) sections.add(_behaviorRules(settings));
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

  static String _coreIdentity(CharacterSettings settings) => '''
【核心身份｜永久层】
角色本名：${settings.characterName}
用户备注：${settings.remark}
与用户关系：${settings.relation}
角色对用户的常用称呼：${settings.userCallName}

${settings.coreProfile}
''';

  static String _behaviorRules(CharacterSettings settings) => '''
【行为规则｜按任务加载】
${settings.behaviorStyle}

【禁止事项】
${settings.forbiddenRules}
''';

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
