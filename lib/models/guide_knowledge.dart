class GuideKnowledgeEntry {
  const GuideKnowledgeEntry({
    required this.topic,
    required this.keywords,
    required this.answer,
  });

  final String topic;
  final List<String> keywords;
  final String answer;
}

class GuideKnowledge {
  const GuideKnowledge._();

  static const privacyBoundary = '阿澈只了解 PeiLink 的公开功能说明，不会读取私人聊天、角色记忆或用户关系数据。';

  static const entries = <GuideKnowledgeEntry>[
    GuideKnowledgeEntry(
      topic: 'Echo 是什么',
      keywords: ['echo', '动态', '生活回声', '生活记录'],
      answer: 'Echo 是角色的生活回声空间，用来呈现公开动态、照片、互动和共同留下的痕迹。',
    ),
    GuideKnowledgeEntry(
      topic: '羁绊系统',
      keywords: ['羁绊', '关系', '亲密度', '等级', '信任'],
      answer: '羁绊会根据真实交流、Echo 互动和礼物逐步成长，不会凭空生成关系进度。',
    ),
    GuideKnowledgeEntry(
      topic: '如何创建角色',
      keywords: ['角色创建', '创建角色', '新角色', '人物'],
      answer: '从创建角色入口填写基础资料，即可建立一个属于你的 AI 角色。',
    ),
    GuideKnowledgeEntry(
      topic: 'API 与 AI 大脑',
      keywords: ['api', '模型', '大脑', '密钥', 'key'],
      answer: '在 AI 大脑设置中选择服务并填写对应 API 配置。Guide 不会读取或展示你的密钥内容。',
    ),
    GuideKnowledgeEntry(
      topic: '.pei 角色导入',
      keywords: ['.pei', 'pei导入', '导入角色', '角色导入'],
      answer: '在角色创建区域选择导入 .pei 文件，并按页面提示确认角色资料。',
    ),
    GuideKnowledgeEntry(
      topic: '数据与隐私',
      keywords: ['隐私', '聊天记录', '角色记忆', '关系数据', '读取数据'],
      answer: privacyBoundary,
    ),
  ];

  static String answer(String question) {
    final normalized = question.trim().toLowerCase().replaceAll(' ', '');
    if (normalized.isEmpty) {
      return '可以问我 PeiLink 的功能，例如 Echo、羁绊、角色创建、API 或 .pei 导入。';
    }
    for (final entry in entries) {
      if (entry.keywords.any(
        (keyword) =>
            normalized.contains(keyword.toLowerCase().replaceAll(' ', '')),
      )) {
        return entry.answer;
      }
    }
    return '这个问题暂时不在公开功能说明里。你可以换个关键词，或通过“帮助与反馈”告诉我们。';
  }
}
