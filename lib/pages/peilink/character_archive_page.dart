import 'package:flutter/material.dart';

import '../../models/character_archive.dart';
import '../../services/character_archive_storage_service.dart';
import '../../theme/app_theme_background.dart';

enum CharacterArchiveSection {
  preferences,
  emotions,
  beliefs,
  dailyLife,
  world,
  language,
  growth,
}

const _archiveFields = <CharacterArchiveSection, List<(String, String)>>{
  CharacterArchiveSection.preferences: [
    ('likes', '喜欢'),
    ('dislikes', '讨厌'),
    ('favoriteFood', '喜欢的食物'),
    ('favoriteColor', '喜欢的颜色'),
    ('favoriteMusic', '喜欢的音乐'),
    ('collections', '收藏'),
    ('smallHabits', '小习惯'),
  ],
  CharacterArchiveSection.emotions: [
    ('inLove', '恋爱后的表现'),
    ('trueAffection', '真正喜欢一个人的表现'),
    ('whenUnhappy', '不开心时'),
    ('whenAngry', '生气时'),
    ('whenJealous', '吃醋时'),
    ('whenAfraid', '害怕时'),
    ('whenVulnerable', '脆弱时'),
  ],
  CharacterArchiveSection.beliefs: [
    ('lifeGoal', '人生目标'),
    ('futureView', '对未来的想法'),
    ('moneyView', '对金钱的态度'),
    ('loveView', '对感情的态度'),
    ('importantPrinciples', '重要原则'),
  ],
  CharacterArchiveSection.dailyLife: [
    ('frequentPlaces', '常去地点'),
    ('friends', '朋友'),
    ('workPartners', '工作伙伴'),
    ('livingHabits', '生活习惯'),
    ('dailyState', '日常状态'),
  ],
  CharacterArchiveSection.world: [
    ('era', '时代背景'),
    ('socialEnvironment', '社会环境'),
    ('importantPlaces', '重要地点'),
    ('rolePosition', '角色定位'),
    ('currentState', '当前状态'),
  ],
  CharacterArchiveSection.language: [
    ('languageHabits', '语言习惯'),
    ('commonExpressions', '常用表达'),
    ('speakingStyle', '说话风格'),
    ('chatPace', '聊天节奏'),
    ('expressionTraits', '表达特点'),
  ],
  CharacterArchiveSection.growth: [
    ('childhoodExperience', '童年经历'),
    ('adolescence', '少年时期'),
    ('turningPoints', '重要转折'),
    ('influentialPeople', '影响人物'),
    ('lifeExperience', '人生经历'),
  ],
};

String _sectionTitle(CharacterArchiveSection section) => switch (section) {
  CharacterArchiveSection.preferences => '喜好与习惯',
  CharacterArchiveSection.emotions => '情感模式',
  CharacterArchiveSection.beliefs => '价值观',
  CharacterArchiveSection.dailyLife => '日常生活',
  CharacterArchiveSection.world => '世界设定',
  CharacterArchiveSection.language => '语言与表达',
  CharacterArchiveSection.growth => '成长经历',
};

class CharacterArchivePage extends StatelessWidget {
  const CharacterArchivePage({
    super.key,
    required this.characterId,
    required this.characterName,
  });

  final String characterId;
  final String characterName;

  @override
  Widget build(BuildContext context) {
    return ThemeBackgroundContainer(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('角色档案'),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$characterName的角色档案',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    '记录生活偏好、情绪反应与世界信息。',
                    style: TextStyle(color: Color(0xFF777777), fontSize: 13),
                  ),
                ],
              ),
            ),
            ...CharacterArchiveSection.values.map(
              (section) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: Colors.white.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(16),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 7,
                    ),
                    title: Text(
                      _sectionTitle(section),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      _archiveFields[section]!
                          .map((item) => item.$2)
                          .join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CharacterArchiveSectionPage(
                          characterId: characterId,
                          section: section,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(6, 5, 6, 0),
              child: Text(
                '档案会按当前聊天内容选择相关部分，不会覆盖旧版人设或 Prompt。',
                style: TextStyle(color: Color(0xFF777777), fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CharacterArchiveSectionPage extends StatefulWidget {
  const CharacterArchiveSectionPage({
    super.key,
    required this.characterId,
    required this.section,
  });

  final String characterId;
  final CharacterArchiveSection section;

  @override
  State<CharacterArchiveSectionPage> createState() =>
      _CharacterArchiveSectionPageState();
}

class _CharacterArchiveSectionPageState
    extends State<CharacterArchiveSectionPage> {
  final Map<String, TextEditingController> _controllers = {};
  CharacterArchive? _archive;
  bool _saving = false;

  List<(String, String)> get _fields => _archiveFields[widget.section]!;

  @override
  void initState() {
    super.initState();
    for (final field in _fields) {
      _controllers[field.$1] = TextEditingController();
    }
    _load();
  }

  Future<void> _load() async {
    final archive = await CharacterArchiveStorageService(
      characterId: widget.characterId,
    ).load();
    for (final field in _fields) {
      _controllers[field.$1]!.text = archive.value(field.$1);
    }
    if (mounted) setState(() => _archive = archive);
  }

  Future<void> _save() async {
    final archive = _archive;
    if (archive == null || _saving) return;
    setState(() => _saving = true);
    final updates = {
      for (final field in _fields)
        field.$1: _controllers[field.$1]!.text.trim(),
    };
    final updated = archive.merge(updates);
    try {
      await CharacterArchiveStorageService(
        characterId: widget.characterId,
      ).save(updated);
      if (!mounted) return;
      setState(() => _archive = updated);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('角色档案已保存')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('保存失败，请稍后重试')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ThemeBackgroundContainer(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(_sectionTitle(widget.section)),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          actions: [
            TextButton(
              onPressed: _archive == null || _saving ? null : _save,
              child: Text(_saving ? '保存中' : '保存'),
            ),
          ],
        ),
        body: _archive == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: _fields
                          .map(
                            (field) => TextField(
                              controller: _controllers[field.$1],
                              minLines: 1,
                              maxLines: 4,
                              decoration: InputDecoration(
                                labelText: field.$2,
                                border: InputBorder.none,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
