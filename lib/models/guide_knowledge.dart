class GuideKnowledgeEntry {
  const GuideKnowledgeEntry({
    required this.category,
    required this.topic,
    required this.keywords,
    required this.answer,
  });

  final String category;
  final String topic;
  final List<String> keywords;
  final String answer;

  bool matches(String rawQuery) {
    final query = GuideKnowledge.normalize(rawQuery);
    if (query.isEmpty) return true;
    return <String>[
      topic,
      answer,
      ...keywords,
    ].any((value) => GuideKnowledge.normalize(value).contains(query));
  }
}

class GuideKnowledge {
  const GuideKnowledge._();

  static const categories = <String>[
    '开始使用',
    '聊天',
    '角色',
    'Memory',
    'Echo',
    'PeiLink Life',
    '纪念日',
    '群聊',
    '外观',
    '数据与重置',
    'API 与模型',
  ];

  static const privacyBoundary =
      'Guide 只提供 PeiLink 的功能说明，不会读取你的聊天、Memory 或关系内容。';

  static const entries = <GuideKnowledgeEntry>[
    GuideKnowledgeEntry(
      category: '开始使用',
      topic: 'PeiLink 是什么？',
      keywords: ['介绍', '是什么'],
      answer: 'PeiLink 是一个让你创建 AI 角色、聊天，并观察多个角色生活动态的本地应用。',
    ),
    GuideKnowledgeEntry(
      category: '开始使用',
      topic: '怎么创建角色？',
      keywords: ['创建角色', '新角色', '人物', '.pei', '导入角色'],
      answer: '点击消息首页右上角的“＋”，可以新建角色或导入 .pei 角色文件。',
    ),
    GuideKnowledgeEntry(
      category: '开始使用',
      topic: '怎么开始聊天？',
      keywords: ['开始聊天', '发消息'],
      answer: '创建角色后，在消息列表点开角色，输入内容并发送即可开始聊天。',
    ),
    GuideKnowledgeEntry(
      category: '开始使用',
      topic: '怎么切换角色？',
      keywords: ['切角色', '换角色', '多个角色'],
      answer: '在消息列表选择不同角色即可进入各自聊天；每个角色的聊天与主要数据会分别保存。',
    ),
    GuideKnowledgeEntry(
      category: '开始使用',
      topic: '蓝蝴蝶是什么？',
      keywords: ['蝴蝶', 'guide', '指南在哪里'],
      answer: '消息首页顶部的蓝蝴蝶是 PeiLink Guide 入口，点它可以随时回到这里。',
    ),
    GuideKnowledgeEntry(
      category: '开始使用',
      topic: '为什么有些功能不能点击？',
      keywords: ['不能点', '点不了', '未开放', '占位'],
      answer: '测试版中部分 Life 应用暂未开放，因此会显示但不能点击。这是当前版本的正常状态。',
    ),

    GuideKnowledgeEntry(
      category: '聊天',
      topic: '怎么和角色聊天？',
      keywords: ['聊天', '对话'],
      answer: '从消息列表进入角色会话。不同角色使用各自的聊天记录，不需要先切换全局角色。',
    ),
    GuideKnowledgeEntry(
      category: '聊天',
      topic: '角色状态是什么意思？',
      keywords: ['状态', '在线', '忙碌', '休息', '睡觉', '外出', '听歌'],
      answer: '在线、忙碌、休息、睡觉、外出和听歌来自角色已有的本地生活状态映射，不是每次打开页面让模型生成的，也不代表真实互联网在线。',
    ),
    GuideKnowledgeEntry(
      category: '聊天',
      topic: '怎么删除当前聊天记录？',
      keywords: ['清空聊天', '删聊天', '删除聊天'],
      answer: '进入聊天设置，在“当前聊天”中选择“删除聊天记录”，确认后会立即清空当前角色的聊天。',
    ),
    GuideKnowledgeEntry(
      category: '聊天',
      topic: '删除聊天记录会删除什么？',
      keywords: ['删除聊天保留', '清聊天影响'],
      answer: '它只清除当前角色的聊天记录。Memory、Echo、Life、关系、角色资料和你的设置都会保留。',
    ),
    GuideKnowledgeEntry(
      category: '聊天',
      topic: '怎么重新开始角色？',
      keywords: ['重新开始', '重置角色'],
      answer: '在聊天设置或角色管理底部选择“重新开始角色”，阅读提示并确认即可。',
    ),
    GuideKnowledgeEntry(
      category: '聊天',
      topic: '删除聊天和重新开始有什么区别？',
      keywords: ['区别', '清理与重置', '重置'],
      answer: '删除聊天只清空对话；重新开始还会清除当前角色这段生活里自动产生的 Echo 和生活轨迹，然后重新开始。',
    ),
    GuideKnowledgeEntry(
      category: '聊天',
      topic: '聊天背景在哪里设置？',
      keywords: ['聊天背景', '背景'],
      answer: '进入当前角色的聊天设置，在“当前聊天”中选择“设置当前聊天背景”。',
    ),
    GuideKnowledgeEntry(
      category: '聊天',
      topic: '怎么重新生成或回溯消息？',
      keywords: ['重新生成', '回溯到这里', '怎么回溯消息', '长按消息', '撤回后续'],
      answer: '长按聊天消息可选择“重新生成”或“回溯到这里”。确认后，重新生成会替换对应回复；回溯会保留当前消息并删除它之后的聊天。',
    ),
    GuideKnowledgeEntry(
      category: '聊天',
      topic: '怎么发送、查看或保存聊天图片？',
      keywords: ['发送图片', '查看图片', '保存图片', '图片怎么保存', '图片预览', '缩放图片', '相册'],
      answer: '点输入框旁的“＋”选择图片并发送。点击聊天中的用户图片或角色生成图片可全屏查看、缩放，并用右上角按钮保存到系统相册。',
    ),

    GuideKnowledgeEntry(
      category: '角色',
      topic: '角色设置在哪里？',
      keywords: ['角色设置', '人物设置', '编辑角色设定', '修改人设', '怎么修改角色人设'],
      answer: '进入聊天设置，在“角色管理”中选择“编辑角色设定”，即可修改创建时填写的人设并保存。',
    ),
    GuideKnowledgeEntry(
      category: '角色',
      topic: '“我的个人设定”是什么？',
      keywords: ['我的个人设定', '个人设定', '角色眼中的我'],
      answer: '它描述你在当前角色世界里的身份，只属于这个角色，不会修改侧边栏中的真实个人资料；保存后会用于该角色之后的对话。',
    ),
    GuideKnowledgeEntry(
      category: '角色',
      topic: '怎么导出角色？',
      keywords: ['导出角色', '.pei'],
      answer: '在聊天设置或角色管理选择“导出角色”，按系统提示保存 .pei 文件。',
    ),
    GuideKnowledgeEntry(
      category: '角色',
      topic: '怎么删除角色？',
      keywords: ['删除角色', '永久删除'],
      answer: '在角色管理底部选择“删除角色”，经过两次确认后永久删除。',
    ),
    GuideKnowledgeEntry(
      category: '角色',
      topic: '删除角色后能恢复吗？',
      keywords: ['恢复角色', '撤销删除'],
      answer: '不能。删除角色是永久操作，请先确认不再需要该角色及其独立数据。',
    ),
    GuideKnowledgeEntry(
      category: '角色',
      topic: '多个角色的数据会混在一起吗？',
      keywords: ['串角色', '数据混', '角色隔离'],
      answer: '聊天、Memory、角色资料和主要生活数据都按角色分别保存。进入页面时会读取对应角色的数据。',
    ),
    GuideKnowledgeEntry(
      category: '角色',
      topic: '羁绊是什么？',
      keywords: ['羁绊', '关系成长', '亲密度'],
      answer: '羁绊记录你与角色的关系进度，会根据已有的真实交流与正式互动逐步变化。',
    ),

    GuideKnowledgeEntry(
      category: 'Memory',
      topic: 'Memory 是什么？',
      keywords: ['memory', '记忆', '为什么他忘了'],
      answer: 'Memory 用来保存希望角色长期记住的重要内容。它与普通聊天记录分开保存。',
    ),
    GuideKnowledgeEntry(
      category: 'Memory',
      topic: '怎么新增记忆？',
      keywords: ['新增记忆', '添加记忆'],
      answer:
          '进入聊天设置，在“角色管理”中打开 Memory。你可以在“Ta 心中的我”添加关于你的记忆，或在“经历过的事”中选择“添加经历”。',
    ),
    GuideKnowledgeEntry(
      category: 'Memory',
      topic: '什么是长期记忆？',
      keywords: ['长期记忆'],
      answer: 'Memory 中关于你的认识、共同经历和记忆汇总会长期保存在当前角色范围内；其中的内容可按页面现有操作编辑、固定或删除。',
    ),
    GuideKnowledgeEntry(
      category: 'Memory',
      topic: '自动记忆是什么？',
      keywords: ['自动记忆', '自动整理', '候选记忆'],
      answer: '开启“自动记忆”后，角色会在聊天一段时间后整理值得记住的内容。你仍可在 Memory 页面查看和管理这些记忆。',
    ),
    GuideKnowledgeEntry(
      category: 'Memory',
      topic: '记忆汇总是什么？',
      keywords: ['记忆汇总', '更新总结', '整理记忆'],
      answer: '记忆汇总是一份长期保留的相处总结。你可以手动编辑，也可以点“更新总结”让 AI 根据当前角色的记忆重新整理。',
    ),
    GuideKnowledgeEntry(
      category: 'Memory',
      topic: 'Memory 会不会串角色？',
      keywords: ['memory串角色', '记忆隔离'],
      answer: '不会。当前角色的聊天、待审核内容和长期 Memory 都使用同一个角色范围保存。',
    ),
    GuideKnowledgeEntry(
      category: 'Memory',
      topic: '清聊天或重新开始会删 Memory 吗？',
      keywords: ['删除聊天memory', '重新开始memory', '重置记忆'],
      answer: '不会。删除聊天记录和重新开始角色都会保留长期 Memory。',
    ),

    GuideKnowledgeEntry(
      category: 'Echo',
      topic: 'Echo 是什么？',
      keywords: ['echo', '动态', '朋友圈', '生活回声'],
      answer: 'Echo 是角色的生活回声空间，用来呈现角色动态、图片和互动。',
    ),
    GuideKnowledgeEntry(
      category: 'Echo',
      topic: 'Echo 和聊天有什么区别？',
      keywords: ['echo区别'],
      answer: '聊天是你与角色的直接对话；Echo 更像角色公开留下的生活动态和互动空间。',
    ),
    GuideKnowledgeEntry(
      category: 'Echo',
      topic: '角色为什么会自己发 Echo？',
      keywords: ['自动echo', '自己发动态'],
      answer: '角色会根据现有生活运行规则，在合适时留下 Echo。打开 Guide 不会额外生成 Echo。',
    ),
    GuideKnowledgeEntry(
      category: 'Echo',
      topic: 'Echo 里的评论是什么？',
      keywords: ['echo评论', '评论'],
      answer: '评论是 Echo 下的互动内容。不同角色和用户可以按当前正式规则参与。',
    ),
    GuideKnowledgeEntry(
      category: 'Echo',
      topic: '不同角色会出现在 Echo 里吗？',
      keywords: ['多角色echo'],
      answer: '会。公共 Echo 时间线可以聚合多个角色的正式 Echo，每条内容仍保留自己的角色来源。',
    ),
    GuideKnowledgeEntry(
      category: 'Echo',
      topic: '删除聊天会删除 Echo 吗？',
      keywords: ['删除聊天echo'],
      answer: '不会。只删除聊天记录时，Echo 会保留。',
    ),
    GuideKnowledgeEntry(
      category: 'Echo',
      topic: '重新开始角色后 Echo 会怎样？',
      keywords: ['重新开始echo', '重置echo'],
      answer: '重新开始会清除当前角色这段生活中自动产生的 Echo 和相关运行痕迹，并重新初始化角色的第一条 Echo。',
    ),

    GuideKnowledgeEntry(
      category: 'PeiLink Life',
      topic: 'PeiLink Life 是什么？',
      keywords: ['life', '生活世界'],
      answer: 'PeiLink Life 是观察所有角色生活动态与本地生活工具的首页。',
    ),
    GuideKnowledgeEntry(
      category: 'PeiLink Life',
      topic: '最近动态是什么？',
      keywords: ['最近动态', '生活动态'],
      answer:
          '最近动态聚合多个角色已有的 Life Moment、Echo 和生活轨迹，按时间显示角色、事件和发生时间，不会为了热闹临时生成事件。',
    ),
    GuideKnowledgeEntry(
      category: 'PeiLink Life',
      topic: '世界状态是什么？',
      keywords: ['世界状态'],
      answer: '世界状态描述 PeiLink World 当前的整体运行展示，不是某个角色的互联网在线状态。',
    ),
    GuideKnowledgeEntry(
      category: 'PeiLink Life',
      topic: '日历现在能做什么？',
      keywords: ['日历', '月历'],
      answer: '当前日历是本地基础月历，可以查看年月日和选中日期，不读取角色生活，也不会生成 AI 日程。',
    ),
    GuideKnowledgeEntry(
      category: 'PeiLink Life',
      topic: '生活应用为什么不能点？',
      keywords: ['相册', '音乐', '礼物', '日记', '世界', 'life app'],
      answer: '相册、音乐、礼物、日记和世界在当前测试版尚未开放，因此暂时不可点击。',
    ),

    GuideKnowledgeEntry(
      category: '纪念日',
      topic: '怎么添加纪念日？',
      keywords: ['纪念日', '倒数日', '新增纪念日'],
      answer: '点击 Life 首页的纪念日卡片，进入纪念日页面后点击右上角“＋”。',
    ),
    GuideKnowledgeEntry(
      category: '纪念日',
      topic: '纪念日支持哪些日期？',
      keywords: ['纪念日期', '过去日期', '未来日期'],
      answer: '可以记录过去或未来的日期。页面会显示已经过去多少天，或距离日期还有多少天。',
    ),
    GuideKnowledgeEntry(
      category: '纪念日',
      topic: '纪念日可以每年重复吗？',
      keywords: ['每年重复', '周年'],
      answer: '可以。重复方式支持“不重复”和“每年”。',
    ),
    GuideKnowledgeEntry(
      category: '纪念日',
      topic: '纪念日可以关联角色吗？',
      keywords: ['关联角色'],
      answer: '可以选择一个角色作为轻量关联。角色被删除后，纪念日本身仍会保留。',
    ),
    GuideKnowledgeEntry(
      category: '纪念日',
      topic: '什么是置顶到 Life 首页？',
      keywords: ['置顶纪念日', 'life首页'],
      answer: '置顶后，该纪念日会显示在 Life 首页卡片中。同一时间只会有一个正式置顶项。',
    ),
    GuideKnowledgeEntry(
      category: '纪念日',
      topic: '纪念日会影响角色聊天吗？',
      keywords: ['纪念日prompt', '纪念日聊天', '主动祝福'],
      answer: '不会。纪念日目前是独立的本地生活工具，不进入聊天，也不会自动触发角色回复、祝福或 Echo。',
    ),

    GuideKnowledgeEntry(
      category: '群聊',
      topic: '怎么创建群聊？',
      keywords: ['创建群聊', '怎么创建群聊', '多人聊天', '多个角色一起聊'],
      answer: '点击消息首页右上角“＋”，选择“创建群聊”，填写群名称并选择至少两个角色后创建。',
    ),
    GuideKnowledgeEntry(
      category: '群聊',
      topic: '群聊可以设置什么？',
      keywords: ['群聊设置', '群名称', '群成员', '群聊身份', '退出群聊'],
      answer: '从群聊右上角进入“群聊设置”，可以管理成员、我的群聊身份、群名称、消息免打扰、置顶、清空记录或删除并退出群聊。',
    ),

    GuideKnowledgeEntry(
      category: '外观',
      topic: '主题和聊天气泡在哪里设置？',
      keywords: ['主题装扮', '个性装扮', '聊天气泡', '聊天气泡在哪', '字体', '背景'],
      answer: '打开消息首页左上角的个人侧栏，选择“主题装扮”。在“个性装扮”中可以分别选择背景、聊天气泡和字体。',
    ),

    GuideKnowledgeEntry(
      category: '数据与重置',
      topic: '删除聊天记录会保留什么？',
      keywords: ['清空聊天', '删聊天', 'chat history'],
      answer: '删除聊天只清除当前角色的对话。Memory、Echo、生活轨迹、关系、角色资料和用户设置都会保留。',
    ),
    GuideKnowledgeEntry(
      category: '数据与重置',
      topic: '重新开始角色会清除什么？',
      keywords: ['重新开始', '重置', '清理与重置'],
      answer: '重新开始会清除当前角色这段生活中自动产生的聊天、Echo 和生活轨迹，然后重新开始角色生活。',
    ),
    GuideKnowledgeEntry(
      category: '数据与重置',
      topic: '重新开始角色会保留什么？',
      keywords: ['重置保留'],
      answer: '角色资料、角色档案、长期 Memory、关系进度、礼物、纪念日、用户设置以及 API 配置都会保留。',
    ),
    GuideKnowledgeEntry(
      category: '数据与重置',
      topic: '重新开始和删除角色有什么区别？',
      keywords: ['删除角色区别'],
      answer: '重新开始会保留角色本身和长期资料；删除角色会永久删除该角色及其独立数据，无法撤销。',
    ),

    GuideKnowledgeEntry(
      category: 'API 与模型',
      topic: 'PeiLink 为什么需要 API？',
      keywords: ['为什么api'],
      answer: 'PeiLink 需要连接你配置的模型服务，才能生成聊天回复和其他需要模型的内容。',
    ),
    GuideKnowledgeEntry(
      category: 'API 与模型',
      topic: '在哪里设置 API？',
      keywords: ['设置api', 'api key', '密钥'],
      answer: '可以点击 Guide 首页的“AI 大脑设置”，也可以从设置页进入模型与 API 配置。',
    ),
    GuideKnowledgeEntry(
      category: 'API 与模型',
      topic: 'PeiLink 自带模型吗？',
      keywords: ['自带模型', '免费模型'],
      answer: '当前测试版不内置可直接使用的云端模型，需要配置受支持的模型服务。',
    ),
    GuideKnowledgeEntry(
      category: 'API 与模型',
      topic: '可以切换模型吗？',
      keywords: ['切换模型', '换模型', 'provider'],
      answer: '可以。在 AI 大脑设置中选择服务并配置对应模型；可用范围取决于你的服务账户。',
    ),
    GuideKnowledgeEntry(
      category: 'API 与模型',
      topic: 'API Key 保存在哪里？',
      keywords: ['api key保存在哪里', 'key保存', '密钥安全', 'api安全吗'],
      answer: 'API Key 通过设备系统提供的安全存储能力保存在本机，并在调用你选择的模型服务时使用。Guide 不会读取或显示密钥内容。',
    ),
    GuideKnowledgeEntry(
      category: 'API 与模型',
      topic: 'Guide 会读取私人数据吗？',
      keywords: ['隐私', '读取聊天', '读取memory', '看聊天记录', '能看我的聊天'],
      answer: privacyBoundary,
    ),
  ];

  static String normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

  static String answer(String question) {
    final normalized = normalize(question);
    if (normalized.isEmpty) {
      return '可以问我聊天、角色、Memory、Echo、Life、纪念日、数据重置或 API 设置。';
    }
    GuideKnowledgeEntry? bestMatch;
    var bestKeywordLength = 0;
    for (final entry in entries) {
      for (final keyword in entry.keywords) {
        final normalizedKeyword = normalize(keyword);
        if (normalized.contains(normalizedKeyword) &&
            normalizedKeyword.length > bestKeywordLength) {
          bestMatch = entry;
          bestKeywordLength = normalizedKeyword.length;
        }
      }
    }
    if (bestMatch != null) return bestMatch.answer;
    for (final entry in entries) {
      if (entry.matches(normalized)) return entry.answer;
    }
    return '这个问题暂时不在公开功能说明里。可以换个关键词，或通过“反馈与建议”告诉我们。';
  }
}
