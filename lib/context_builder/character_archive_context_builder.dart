import '../models/character_archive.dart';

/// Selects only the archive sections relevant to the current user message and
/// renders them as compact natural-language context instead of raw JSON.
class CharacterArchiveContextBuilder {
  const CharacterArchiveContextBuilder({this.maxCharacters = 1000});

  final int maxCharacters;

  static const _sections = <String, List<(String, String)>>{
    'preferences': [
      ('likes', '喜欢'),
      ('dislikes', '讨厌'),
      ('favoriteFood', '喜欢的食物'),
      ('favoriteColor', '喜欢的颜色'),
      ('favoriteMusic', '喜欢的音乐'),
      ('collections', '收藏'),
      ('smallHabits', '小习惯'),
    ],
    'emotions': [
      ('inLove', '恋爱后的表现'),
      ('trueAffection', '真正喜欢一个人的表现'),
      ('whenUnhappy', '不开心时'),
      ('whenAngry', '生气时'),
      ('whenJealous', '吃醋时'),
      ('whenAfraid', '害怕时'),
      ('whenVulnerable', '脆弱时'),
    ],
    'beliefs': [
      ('lifeGoal', '人生目标'),
      ('futureView', '对未来的想法'),
      ('moneyView', '对金钱的态度'),
      ('loveView', '对感情的态度'),
      ('importantPrinciples', '重要原则'),
    ],
    'dailyLife': [
      ('frequentPlaces', '常去地点'),
      ('friends', '朋友'),
      ('workPartners', '工作伙伴'),
      ('livingHabits', '生活习惯'),
      ('dailyState', '日常状态'),
    ],
    'world': [
      ('era', '时代背景'),
      ('socialEnvironment', '社会环境'),
      ('importantPlaces', '重要地点'),
      ('rolePosition', '角色定位'),
      ('currentState', '当前状态'),
    ],
    'language': [
      ('languageHabits', '语言习惯'),
      ('commonExpressions', '常用表达'),
      ('speakingStyle', '说话风格'),
      ('chatPace', '聊天节奏'),
      ('expressionTraits', '表达特点'),
    ],
    'growth': [
      ('childhoodExperience', '童年经历'),
      ('adolescence', '少年时期'),
      ('turningPoints', '重要转折'),
      ('influentialPeople', '影响人物'),
      ('lifeExperience', '人生经历'),
    ],
  };

  static const _titles = <String, String>{
    'preferences': '喜好与习惯',
    'emotions': '情感模式',
    'beliefs': '价值观',
    'dailyLife': '日常生活',
    'world': '世界设定',
    'language': '语言与表达',
    'growth': '成长经历',
  };

  String build({
    required CharacterArchive archive,
    required String latestUserMessage,
  }) {
    if (archive.values.isEmpty || maxCharacters <= 0) return '';
    final selected = _selectSections(latestUserMessage);
    final sections = <String>[];
    for (final section in selected) {
      final facts = <String>[];
      for (final field in _sections[section]!) {
        final value = archive.value(field.$1).trim();
        if (value.isNotEmpty) facts.add('${field.$2}：$value');
      }
      if (facts.isNotEmpty) {
        sections.add('【${_titles[section]}】\n${facts.join('；')}。');
      }
    }
    return _truncate(sections.join('\n'), maxCharacters);
  }

  Set<String> _selectSections(String message) {
    final text = message.toLowerCase();
    final selected = <String>{};
    if (_containsAny(text, const [
      '喜欢',
      '讨厌',
      '爱好',
      '习惯',
      '吃什么',
      '颜色',
      '音乐',
      '收藏',
    ])) {
      selected.add('preferences');
    }
    if (_containsAny(text, const [
      '小时候',
      '童年',
      '少年',
      '长大',
      '成长',
      '经历',
      '过去',
      '转折',
    ])) {
      selected.add('growth');
    }
    if (_containsAny(text, const [
      '钱',
      '金钱',
      '未来',
      '人生',
      '目标',
      '原则',
      '价值观',
      '感情怎么看',
    ])) {
      selected.add('beliefs');
    }
    if (_containsAny(text, const ['世界', '时代', '社会', '地点', '在哪里', '背景设定'])) {
      selected.add('world');
    }
    return selected.isEmpty
        ? <String>{'emotions', 'dailyLife', 'language'}
        : selected;
  }

  bool _containsAny(String text, List<String> keywords) =>
      keywords.any(text.contains);

  String _truncate(String value, int limit) {
    if (value.length <= limit) return value;
    if (limit <= 1) return value.substring(0, limit);
    return '${value.substring(0, limit - 1).trimRight()}…';
  }
}
