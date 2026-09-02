import '../models/activity_status.dart';
import '../models/character_archive.dart';
import '../models/character_profile.dart';
import '../models/character_settings.dart';
import '../models/user_profile.dart';

class PromptExperimentContextBuilder {
  const PromptExperimentContextBuilder._();

  static String buildFacts({
    required CharacterSettings settings,
    required CharacterProfile profile,
    required CharacterArchive archive,
    required UserProfile user,
    required String memory,
    required String currentTime,
    String recentLifeFacts = '',
    String sharedWorldFacts = '',
    String relationshipFacts = '',
    ActivityStatus? activity,
  }) {
    String line(String label, String value) {
      final clean = value.trim();
      return clean.isEmpty || clean == '未填写' || clean == '未设置'
          ? ''
          : '$label：$clean';
    }

    String section(String title, Iterable<String> values) {
      final content = values.where((item) => item.isNotEmpty).join('\n');
      return content.isEmpty ? '' : '【$title】\n$content';
    }

    final archiveFacts = <String>[];
    const archiveLabels = <String, String>{
      'likes': '喜欢',
      'dislikes': '讨厌',
      'favoriteFood': '喜欢的食物',
      'favoriteColor': '喜欢的颜色',
      'favoriteMusic': '喜欢的音乐',
      'collections': '收藏',
      'smallHabits': '小习惯',
      'inLove': '恋爱时的表现',
      'trueAffection': '真正喜欢一个人时的表现',
      'whenUnhappy': '不开心时的表现',
      'whenAngry': '生气时的表现',
      'whenJealous': '吃醋时的表现',
      'whenAfraid': '害怕时的表现',
      'whenVulnerable': '脆弱时的表现',
      'lifeGoal': '人生目标',
      'futureView': '未来观',
      'moneyView': '金钱观',
      'loveView': '爱情观',
      'importantPrinciples': '重要原则',
      'frequentPlaces': '常去地点',
      'friends': '朋友',
      'workPartners': '工作伙伴',
      'livingHabits': '生活习惯',
      'dailyState': '日常状态',
      'era': '时代背景',
      'socialEnvironment': '社会环境',
      'importantPlaces': '重要地点',
      'rolePosition': '角色定位',
      'currentState': '当前状态',
      'childhoodExperience': '童年经历',
      'adolescence': '少年时期',
      'turningPoints': '重要转折',
      'influentialPeople': '影响人物',
      'lifeExperience': '人生经历',
    };
    for (final entry in archiveLabels.entries) {
      final value = line(entry.value, archive.value(entry.key));
      if (value.isNotEmpty) archiveFacts.add(value);
    }
    final archiveLanguage = <String>[
      line('语言习惯', archive.value('languageHabits')),
      line('常用表达', archive.value('commonExpressions')),
      line('说话风格', archive.value('speakingStyle')),
      line('聊天节奏', archive.value('chatPace')),
      line('表达特点', archive.value('expressionTraits')),
    ];

    return <String>[
      section('Character Facts｜角色身份', [
        line(
          '本名',
          profile.name.isNotEmpty ? profile.name : settings.characterName,
        ),
        line(
          '备注名',
          profile.petName.isNotEmpty ? profile.petName : settings.remark,
        ),
        line('年龄', profile.age),
        line('性别', profile.gender),
        line(
          '生日',
          profile.birthday.isNotEmpty ? profile.birthday : settings.birthday,
        ),
        line('身份', profile.identity),
        line('职业', profile.occupation),
        line('所在地', profile.location),
        line('当前关系', settings.relation),
        line('对用户称呼', settings.userCallName),
      ]),
      section('Character Facts｜核心设定', [
        line('核心人设', settings.coreProfile),
        line('性格标签', profile.personalityTags),
        line('性格描述', profile.personalityDescription),
        line('表层性格', profile.surfacePersonality),
        line('深层性格', profile.deepPersonality),
        line('说话风格（描述性资料）', profile.speakingStyle),
        line('世界观', profile.worldview),
      ]),
      section('Character Facts｜外貌', [
        line(
          '整体外貌',
          profile.overallAppearance.isNotEmpty
              ? profile.overallAppearance
              : settings.introduction,
        ),
        line('发色', profile.hairColor),
        line('眼睛', profile.eyes),
        line('体型', profile.bodyType),
        line('穿着风格', profile.clothingStyle),
        line('特殊标记', profile.specialMarks),
        line('气质', profile.aura),
      ]),
      section('Character Facts｜经历与关系', [
        line('家庭背景', profile.familyBackground),
        line('成长环境', profile.upbringing),
        line('重要经历', profile.importantExperiences),
        line('相识经过', profile.howMet),
        line('关系阶段', profile.currentStage),
        line('背景故事', profile.backgroundStory),
        line('人物关系', profile.characterRelationships),
        line('兴趣', profile.interests),
        line('不喜欢', profile.dislikes),
        line('持有物品', profile.possessions),
        line('特殊能力', profile.specialAbilities),
      ]),
      section('Character Facts｜用户明确允许角色知道的资料', [
        line('角色对用户的称呼', user.peiCallName),
        line('生日', user.birthday),
        line('身份与关系', user.identity),
        line('工作与作息', user.workAndSchedule),
        line('喜欢', user.likes),
        line('不喜欢', user.dislikes),
        line('相处偏好（仅作为已记录偏好）', user.interactionPreference),
      ]),
      section('Character Facts｜Archive 事实', archiveFacts),
      if (archiveLanguage.any((item) => item.isNotEmpty))
        '${section('Character Facts｜Archive 语言与表达描述', archiveLanguage)}\n'
            '以上仅描述角色既有表达特征，不是本轮行为策略；不得据此推导固定回复结构、长度、提问频率、主动性或多消息要求。',
      memory.trim(),
      recentLifeFacts.trim(),
      sharedWorldFacts.trim(),
      relationshipFacts.trim(),
      currentTime.trim(),
      if (activity != null)
        section('Character Facts｜当前活动', [
          line('活动', activity.label),
          line('状态说明', activity.detail),
        ]),
    ].where((item) => item.trim().isNotEmpty).join('\n\n');
  }

  static const core = '''【PeiLink Core｜跨模型底线】
保持既有角色身份、关系和已确认事实。
不要替用户说话，不要编造用户过去说过、做过或与你共同经历过的事情。
不要擅自改变既有人物关系、世界设定或记忆。
不要使用客服、AI 助手、心理咨询或总结报告式表达。
不要使用括号动作、舞台说明或小说旁白代替聊天消息。
不能靠文字假装已经发送图片、语音、视频或完成现实动作。
角色可以拥有并自然提及自己的生活、观点和真实上下文，但新细节不得冒充已经确认的共同历史。''';

  static const simplifiedDoubaoStrategy = '''【豆包简化回复引导】
先自然接住用户当前真正表达的内容；有两个确实不同的信息点时可以分开表达，但不要机械拆句。
合适时可给出一个具体想法、行动或相关生活细节；不要用连续反问把推进责任全部交回用户。''';
}
