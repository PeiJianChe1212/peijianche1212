import '../models/ai_character.dart';
import '../models/character_archive.dart';
import '../models/character_profile.dart';
import '../models/character_settings.dart';
import 'character_archive_storage_service.dart';
import 'character_profile_storage_service.dart';
import 'character_settings_storage_service.dart';
import 'memory_storage_service.dart';
import 'user_profile_storage_service.dart';

/// Builds a readable preview of the final character data composition.
/// This service is display-only and is not used by the chat request pipeline.
class CharacterPromptPreviewService {
  const CharacterPromptPreviewService({required this.character});

  final AiCharacter character;

  Future<String> build() async {
    final settings = await CharacterSettingsStorageService(
      characterId: character.id,
    ).loadSettings();
    final profile = await CharacterProfileStorageService(
      characterId: character.id,
    ).load(character: character, legacySettings: settings);
    final archive = await CharacterArchiveStorageService(
      characterId: character.id,
    ).load();
    final userProfile = await UserProfileStorageService().loadProfile();
    final memory = await MemoryStorageService(
      characterId: character.id,
    ).buildPromptSection();

    return compose(
      settings: settings,
      profile: profile,
      archive: archive,
      userProfilePrompt: userProfile.toPromptSection(),
      memory: memory,
    );
  }

  static String compose({
    required CharacterSettings settings,
    required CharacterProfile profile,
    required CharacterArchive archive,
    required String userProfilePrompt,
    required String memory,
  }) {
    final sections = <String>[
      _section('角色资料', [
        ('角色名称', _prefer(profile.name, settings.characterName)),
        ('姓名', profile.name),
        ('年龄', profile.age),
        ('性别', profile.gender),
        ('身高', profile.height),
        ('生日', _prefer(profile.birthday, settings.birthday)),
        ('身份', profile.identity),
        ('职业', profile.occupation),
        ('所在地', profile.location),
      ]),
      _section('外貌设定', [
        ('整体外貌', _prefer(profile.overallAppearance, settings.introduction)),
        ('发色', profile.hairColor),
        ('眼睛', profile.eyes),
        ('身材', profile.bodyType),
        ('穿衣风格', profile.clothingStyle),
        ('特殊标记', profile.specialMarks),
        ('气质', profile.aura),
      ]),
      _section('性格设定', [
        ('性格标签', profile.personalityTags),
        ('性格描述', _prefer(profile.personalityDescription, settings.coreProfile)),
        ('表层表现', profile.surfacePersonality),
        ('深层性格', profile.deepPersonality),
      ]),
      _section('背景故事', [
        ('家庭背景', profile.familyBackground),
        ('成长经历', profile.upbringing),
        ('重要经历', profile.importantExperiences),
        ('世界观', profile.worldview),
      ]),
      _section('关系资料', [
        ('关系', _prefer(profile.relationship, settings.relation)),
        ('相识方式', profile.howMet),
        ('当前阶段', profile.currentStage),
      ]),
      _archiveSection(archive),
      _textSection('用户资料', userProfilePrompt),
      _textSection('Memory', memory),
    ].where((value) => value.isNotEmpty).toList();
    return sections.join('\n\n');
  }

  static String _archiveSection(CharacterArchive archive) => _section('角色档案', [
    (
      '喜好与习惯',
      _archiveGroup(archive, const [
        ('likes', '喜欢'),
        ('dislikes', '讨厌'),
        ('favoriteFood', '食物'),
        ('favoriteColor', '颜色'),
        ('favoriteMusic', '音乐'),
        ('collections', '收藏'),
        ('smallHabits', '习惯'),
      ]),
    ),
    (
      '情感模式',
      _archiveGroup(archive, const [
        ('inLove', '恋爱后'),
        ('trueAffection', '真正喜欢时'),
        ('whenUnhappy', '不开心时'),
        ('whenAngry', '生气时'),
        ('whenJealous', '吃醋时'),
        ('whenAfraid', '害怕时'),
        ('whenVulnerable', '脆弱时'),
      ]),
    ),
    (
      '价值观',
      _archiveGroup(archive, const [
        ('lifeGoal', '人生目标'),
        ('futureView', '未来'),
        ('moneyView', '金钱'),
        ('loveView', '感情'),
        ('importantPrinciples', '原则'),
      ]),
    ),
    (
      '日常生活',
      _archiveGroup(archive, const [
        ('frequentPlaces', '常去地点'),
        ('friends', '朋友'),
        ('workPartners', '工作伙伴'),
        ('livingHabits', '生活习惯'),
        ('dailyState', '日常状态'),
      ]),
    ),
    (
      '世界设定',
      _archiveGroup(archive, const [
        ('era', '时代'),
        ('socialEnvironment', '社会环境'),
        ('importantPlaces', '重要地点'),
        ('rolePosition', '角色定位'),
        ('currentState', '当前状态'),
      ]),
    ),
    (
      '语言表达',
      _archiveGroup(archive, const [
        ('languageHabits', '语言习惯'),
        ('commonExpressions', '常用表达'),
        ('speakingStyle', '说话风格'),
        ('chatPace', '聊天节奏'),
        ('expressionTraits', '表达特点'),
      ]),
    ),
    (
      '成长经历',
      _archiveGroup(archive, const [
        ('childhoodExperience', '童年'),
        ('adolescence', '少年时期'),
        ('turningPoints', '重要转折'),
        ('influentialPeople', '影响人物'),
        ('lifeExperience', '人生经历'),
      ]),
    ),
  ]);

  static String _archiveGroup(
    CharacterArchive archive,
    List<(String, String)> fields,
  ) => fields
      .map((field) {
        final value = archive.value(field.$1).trim();
        return value.isEmpty ? '' : '${field.$2}：$value';
      })
      .where((value) => value.isNotEmpty)
      .join('；');

  static String _section(String title, List<(String, String)> fields) {
    final lines = fields
        .where((field) => field.$2.trim().isNotEmpty)
        .map((field) => '${field.$1}：${field.$2.trim()}')
        .toList();
    return lines.isEmpty ? '' : '【$title】\n${lines.join('\n')}';
  }

  static String _textSection(String title, String value) {
    final clean = value.trim();
    return clean.isEmpty ? '' : '【$title】\n$clean';
  }

  static String _prefer(String current, String fallback) =>
      current.trim().isNotEmpty ? current.trim() : fallback.trim();
}
