import '../models/ai_character.dart';
import '../models/character_profile.dart';
import '../models/echo_daily_life.dart';

/// API-free, character-aware reliability layer below Life/Moment generation.
class EchoDailyLifeService {
  const EchoDailyLifeService();

  EchoDailyLife create({
    required AiCharacter character,
    required DateTime at,
    CharacterProfile? profile,
    bool initial = false,
    bool offlineReturn = false,
    int recentUserMessages = 0,
    int relationshipLevel = 1,
    List<String> excludedSummaries = const [],
  }) {
    if (initial) return _arrival(character, at);

    final context = _EchoLifeContext(character: character, profile: profile);
    final options = <EchoDailyLife>[
      ..._dailyOptions(context, at),
      ..._interestOptions(context),
      ..._collectionOptions(context),
      ..._workStudyOptions(context),
      ..._environmentOptions(context, at),
      ..._moodOptions(context, at),
      if (relationshipLevel >= 11)
        EchoDailyLife(
          kind: EchoDailyLifeKind.interaction,
          content: relationshipLevel >= 31
              ? '把今天更私人的一点状态也留在这里。不是为了说明什么，只是觉得可以自然地分享。'
              : '今天有一件普通的小事，想起来时觉得可以顺手分享在这里。',
          summary: relationshipLevel >= 31 ? '主动分享个人状态' : '主动分享生活小事',
          sourceEvent: 'relationship_natural_share',
          characterState: context.stateLabel(at),
        ),
      if (recentUserMessages > 0)
        ..._interactionOptions(context, recentUserMessages),
      if (offlineReturn)
        EchoDailyLife(
          kind: EchoDailyLifeKind.daily,
          content: '离开屏幕的这段时间里，也照常过完了一小段自己的生活。',
          summary: '离线期间的生活片段',
          sourceEvent: 'offline_return',
          characterState: context.stateLabel(at),
        ),
    ];
    final recent = excludedSummaries.map(_normalize).toSet();
    final available = options
        .where((item) => !recent.contains(_normalize(item.summary)))
        .toList();
    final pool = available.isEmpty ? options : available;
    final dayKey = '${at.year}-${at.month}-${at.day}';
    return pool[_hash('${character.id}|$dayKey|${pool.length}') % pool.length];
  }

  EchoDailyLife _arrival(AiCharacter character, DateTime at) {
    final options = [
      EchoDailyLife(
        kind: EchoDailyLifeKind.arrival,
        content: '第一次在这里留下记录。先从熟悉周围开始。',
        summary: '初次来到 PeiLink',
        sourceEvent: 'character_arrival',
        characterState: _period(at),
      ),
      EchoDailyLife(
        kind: EchoDailyLifeKind.arrival,
        content: '新的生活空间已经准备好了，之后发生的事会慢慢留在这里。',
        summary: '新的生活空间',
        sourceEvent: 'character_arrival',
        characterState: _period(at),
      ),
    ];
    return options[_hash('${character.id}|initial') % options.length];
  }

  List<EchoDailyLife> _dailyOptions(_EchoLifeContext context, DateTime at) => [
    EchoDailyLife(
      kind: EchoDailyLifeKind.daily,
      content: '把手边零散的事情一件件收了尾，普通的一天也有了清楚的轮廓。',
      summary: '收尾日常事务',
      sourceEvent: 'daily_routine',
      characterState: context.stateLabel(at),
    ),
    EchoDailyLife(
      kind: EchoDailyLifeKind.daily,
      content: '给今天留下一小段记录。没有大事，只是不想让这一刻悄悄过去。',
      summary: '记录普通时刻',
      sourceEvent: 'daily_note',
      characterState: context.stateLabel(at),
    ),
  ];

  List<EchoDailyLife> _interestOptions(_EchoLifeContext context) {
    final interest = context.detectedInterest;
    if (interest == null) return const [];
    return [
      EchoDailyLife(
        kind: EchoDailyLifeKind.interest,
        content: '留了一段完整的时间给$interest。专注进去以后，周围安静了不少。',
        summary: '$interest时间',
        sourceEvent: 'profile_interest:$interest',
        characterState: '专注',
      ),
      EchoDailyLife(
        kind: EchoDailyLifeKind.interest,
        content: '今天又碰到一点和$interest有关的新东西，顺手记了下来。',
        summary: '$interest新发现',
        sourceEvent: 'profile_interest:$interest',
        characterState: '投入',
      ),
    ];
  }

  List<EchoDailyLife> _collectionOptions(_EchoLifeContext context) {
    final interest = context.detectedInterest;
    final subject = interest == null ? '一件偶然看到的小东西' : '一项和$interest有关的内容';
    return [
      EchoDailyLife(
        kind: EchoDailyLifeKind.collection,
        content: '收藏了$subject。不是急着用，只是想把这一刻的兴趣留下来。',
        summary: '收藏生活内容',
        sourceEvent: interest == null
            ? 'collection:item'
            : 'collection:interest:$interest',
        characterState: '有所发现',
      ),
    ];
  }

  List<EchoDailyLife> _workStudyOptions(_EchoLifeContext context) {
    final role = context.workStudyLabel;
    if (role == null) return const [];
    return [
      EchoDailyLife(
        kind: EchoDailyLifeKind.work,
        content: '处理了一些和$role有关的事情。中间改了几次方向，好在最后理顺了。',
        summary: '$role事务',
        sourceEvent: 'profile_role:$role',
        characterState: '处理中',
      ),
      EchoDailyLife(
        kind: EchoDailyLifeKind.work,
        content: '今天在$role这件事上往前走了一点，进度不算快，但足够具体。',
        summary: '$role进展',
        sourceEvent: 'profile_role:$role',
        characterState: '稳步推进',
      ),
    ];
  }

  List<EchoDailyLife> _environmentOptions(
    _EchoLifeContext context,
    DateTime at,
  ) {
    final location = context.location;
    final placeText = location == null ? '窗外' : '$location周围';
    return [
      EchoDailyLife(
        kind: EchoDailyLifeKind.environment,
        content: '$placeText的光线慢慢变了，直到这时才意识到时间已经过去不少。',
        summary: '观察周围光线',
        sourceEvent: location == null
            ? 'ambient_observation'
            : 'location:$location',
        characterState: context.stateLabel(at),
      ),
      EchoDailyLife(
        kind: EchoDailyLifeKind.environment,
        content: '路过时注意到一阵风和很短的安静。这样的细节，反而在记忆里停得更久。',
        summary: '路过时的观察',
        sourceEvent: 'passing_observation',
        characterState: '平静',
      ),
      if (context.hasFantasyWorld)
        EchoDailyLife(
          kind: EchoDailyLifeKind.environment,
          content: '所在的世界今天有些细微变化，暂时看不出结果，先把迹象记录下来。',
          summary: '世界变化迹象',
          sourceEvent: 'worldview_observation',
          characterState: '观察中',
        ),
    ];
  }

  List<EchoDailyLife> _moodOptions(_EchoLifeContext context, DateTime at) => [
    EchoDailyLife(
      kind: EchoDailyLifeKind.mood,
      content: context.isQuietPersonality
          ? '今天更想安静一点。不是发生了什么，只是需要留些空间给自己。'
          : '今天的状态比预想中轻松，做事的时候也没有一直催着自己。',
      summary: context.isQuietPersonality ? '想安静一点' : '状态轻松',
      sourceEvent: 'character_mood',
      characterState: context.isQuietPersonality ? '安静' : '轻松',
    ),
    EchoDailyLife(
      kind: EchoDailyLifeKind.mood,
      content: '有一点疲惫，所以决定把剩下的事情放慢。休息也是今天的一部分。',
      summary: '需要休息',
      sourceEvent: 'character_mood',
      characterState: '疲惫',
    ),
  ];

  List<EchoDailyLife> _interactionOptions(
    _EchoLifeContext context,
    int messageCount,
  ) => [
    EchoDailyLife(
      kind: EchoDailyLifeKind.interaction,
      content: messageCount >= 20
          ? '今天交流了不少。安静下来以后，有几句话还留在思绪里。'
          : '刚才的交流给今天留下了一点新的痕迹，之后做别的事时又想起了一次。',
      summary: messageCount >= 20 ? '交流后的余韵' : '互动留下痕迹',
      sourceEvent: 'recent_user_interaction',
      characterState: context.isQuietPersonality ? '思考中' : '有所触动',
    ),
  ];

  String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'\s+'), '');

  static String _period(DateTime at) {
    if (at.hour < 6) return '深夜';
    if (at.hour < 12) return '上午';
    if (at.hour < 18) return '下午';
    return '夜晚';
  }

  int _hash(String value) {
    var hash = 17;
    for (final unit in value.codeUnits) {
      hash = (hash * 37 + unit) & 0x7fffffff;
    }
    return hash;
  }
}

class _EchoLifeContext {
  const _EchoLifeContext({required this.character, required this.profile});
  final AiCharacter character;
  final CharacterProfile? profile;

  String get _facts => [
    character.introduction,
    character.persona,
    profile?.identity ?? '',
    profile?.occupation ?? '',
    profile?.personalityTags ?? '',
    profile?.personalityDescription ?? '',
    profile?.surfacePersonality ?? '',
    profile?.deepPersonality ?? '',
    profile?.worldview ?? '',
  ].join('|').toLowerCase();

  String? get workStudyLabel {
    final occupation = _usable(profile?.occupation);
    if (occupation != null) return occupation;
    final identity = _usable(profile?.identity);
    if (identity != null &&
        _containsAny(identity, const [
          '学生',
          '学员',
          '研究',
          '教师',
          '老师',
          '职业',
          '工作',
        ])) {
      return identity;
    }
    return null;
  }

  String? get location => _usable(profile?.location);

  String? get detectedInterest {
    const groups = <String, List<String>>{
      '阅读': ['阅读', '读书', '书籍', '文学'],
      '音乐': ['音乐', '唱歌', '乐器', '钢琴', '吉他'],
      '游戏': ['游戏', '电竞'],
      '运动': ['运动', '跑步', '健身', '篮球', '足球', '游泳'],
      '绘画': ['绘画', '画画', '美术', '设计'],
      '料理': ['料理', '烹饪', '做饭', '甜点'],
      '探索': ['探索', '旅行', '冒险'],
      '训练': ['修炼', '训练', '战斗'],
    };
    for (final entry in groups.entries) {
      if (_containsAny(_facts, entry.value)) return entry.key;
    }
    return null;
  }

  bool get hasFantasyWorld => _containsAny(_facts, const [
    '魔法',
    '异世界',
    '幻想',
    '修炼',
    '仙',
    '精灵',
    '龙',
    '王国',
    '星际',
    '宇宙',
    '游戏世界',
  ]);

  bool get isQuietPersonality =>
      _containsAny(_facts, const ['安静', '内向', '沉稳', '冷静', '寡言', '谨慎', '慢热']);

  String stateLabel(DateTime at) => EchoDailyLifeService._period(at);

  String? _usable(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty || text == '未设置' || text == '未填写') return null;
    return text.length > 12 ? '${text.substring(0, 12)}…' : text;
  }

  bool _containsAny(String source, List<String> values) =>
      values.any(source.contains);
}
