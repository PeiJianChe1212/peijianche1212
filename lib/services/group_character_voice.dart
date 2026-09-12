import '../models/ai_character.dart';
import '../models/character_archive.dart';
import '../models/character_profile.dart';
import '../models/character_settings.dart';

/// G3.3 Character Voice：把「当前发言角色自己」的表达数据整理成群聊生成用的一块。
///
/// 设计约束：
/// - 只读取传入角色的资料，绝不读取群内其他成员，杜绝人格串线。
/// - 不新增字段、不新增模型调用、不新增 storage，只做读取 + 截断。
/// - 群聊规则负责场景，这里只负责「这个人怎么说话」。
///
/// 数据优先级（角色自己的表达数据 > 通用群聊风格 > 旧硬编码模板）：
/// 1. CharacterProfile.speakingStyle
/// 2. CharacterArchive 表达字段（语言习惯 / 常用表达 / 说话风格 / 聊天节奏 / 表达特点）
/// 3. persona 作为人格语义补充（不重复 coreProfile 已有的内容）
/// 4. CharacterSettings.replyLength / exampleDialogues 作为倾向与样本（样本走 styleExamples）
class GroupCharacterVoice {
  const GroupCharacterVoice._();

  /// 整块字符上限，避免 prompt 膨胀。
  static const int maxCharacters = 1000;
  static const int _speakingStyleLimit = 260;
  static const int _archiveLimit = 280;
  static const int _personaLimit = 200;

  static const String _header = '【Character Voice｜本角色专属表达方式｜只属于你，群里其他角色不适用】';
  static const String _footer =
      '以上只描述「怎么表达」（HOW）：语气、句长、标点、口语化与 emoji 倾向。'
      '只模仿表达方式，不要照抄任何示例句，也不要把示例内容当成已经发生的事实。'
      '群聊的通用节奏不得覆盖这里的表达习惯。';

  /// 返回空字符串表示该角色没有任何自己的表达数据，调用方应走 fallback。
  static String build({
    required AiCharacter character,
    CharacterProfile? profile,
    CharacterArchive? archive,
    CharacterSettings? settings,
  }) {
    final lines = <String>[];

    final rawSpeakingStyle = profile?.speakingStyle.trim() ?? '';
    final speakingStyle = _limit(rawSpeakingStyle, _speakingStyleLimit);
    if (speakingStyle.isNotEmpty) {
      lines.add(
        '表达方式（优先执行，按此塑造语气、句长、标点与 emoji 习惯）：$speakingStyle',
      );
    }

    final archiveSpeakingStyle = archive?.value('speakingStyle').trim() ?? '';
    final archiveLines = <String>[
      _labeled('语言习惯', archive?.value('languageHabits') ?? ''),
      _labeled('常用表达', archive?.value('commonExpressions') ?? ''),
      // 与 CharacterProfile.speakingStyle 完全相同的内容不重复输出。
      _labeled(
        '说话风格',
        archiveSpeakingStyle == rawSpeakingStyle ? '' : archiveSpeakingStyle,
      ),
      _labeled('聊天节奏', archive?.value('chatPace') ?? ''),
      _labeled('表达特点', archive?.value('expressionTraits') ?? ''),
    ].where((value) => value.isNotEmpty).join('\n');
    if (archiveLines.isNotEmpty) {
      lines.add('表达习惯：\n${_limit(archiveLines, _archiveLimit)}');
    }

    final persona = character.persona.trim();
    final coreProfile = settings?.coreProfile.trim() ?? '';
    final personaAlreadyPresent = coreProfile.isNotEmpty && coreProfile.contains(persona);
    if (persona.isNotEmpty && !personaAlreadyPresent) {
      lines.add(
        '人格语义补充（只影响表达气质，不改变上面的表达方式）：'
        '${_limit(persona, _personaLimit)}',
      );
    }

    final tendency = _replyLengthTendency(settings);
    if (tendency.isNotEmpty) lines.add(tendency);

    if (lines.isEmpty) return '';
    final bodyBudget = maxCharacters - _header.length - _footer.length - 4;
    final body = _limit(lines.join('\n'), bodyBudget < 240 ? 240 : bodyBudget);
    return '$_header\n$body\n$_footer';
  }

  /// replyLength 只作为「倾向」，不构成字数 KPI。
  static String _replyLengthTendency(CharacterSettings? settings) {
    return switch (settings?.replyLength) {
      'short' => '表达长度倾向：偏短，几句话说完即可，不主动展开长篇解释。',
      'long' => '表达长度倾向：话题需要时可以从容展开几句，但仍以本角色自己的表达习惯为准。',
      _ => '',
    };
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
}
