import 'package:flutter/material.dart';

import '../../models/ai_character.dart';
import '../../models/character_profile.dart';
import '../../services/character_profile_storage_service.dart';
import '../../services/character_registry_service.dart';
import '../../services/character_settings_storage_service.dart';
import '../../theme/app_theme_background.dart';

enum CharacterProfileSection {
  basic,
  appearance,
  personality,
  background,
  relationship,
}

class CharacterProfileSectionPage extends StatefulWidget {
  const CharacterProfileSectionPage({
    super.key,
    required this.characterId,
    required this.section,
  });
  final String characterId;
  final CharacterProfileSection section;

  @override
  State<CharacterProfileSectionPage> createState() =>
      _CharacterProfileSectionPageState();
}

class _CharacterProfileSectionPageState
    extends State<CharacterProfileSectionPage> {
  final Map<String, TextEditingController> _controllers = {};
  CharacterProfile? _profile;
  bool _saving = false;

  static const _definitions = {
    CharacterProfileSection.basic: [
      ('name', '姓名'),
      ('petName', '小名'),
      ('socialId', '网名 / ID'),
      ('age', '年龄'),
      ('gender', '性别'),
      ('height', '身高'),
      ('birthday', '生日'),
      ('identity', '身份'),
      ('occupation', '职业'),
      ('location', '所在地'),
    ],
    CharacterProfileSection.appearance: [
      ('overallAppearance', '整体外貌'),
      ('hairColor', '发色'),
      ('eyes', '眼睛'),
      ('bodyType', '身材'),
      ('clothingStyle', '穿衣风格'),
      ('specialMarks', '特殊标记'),
      ('aura', '气质'),
    ],
    CharacterProfileSection.personality: [
      ('personalityTags', '性格标签'),
      ('personalityDescription', '性格描述'),
      ('surfacePersonality', '表层表现'),
      ('deepPersonality', '深层性格'),
    ],
    CharacterProfileSection.background: [
      ('familyBackground', '家庭背景'),
      ('upbringing', '成长经历'),
      ('importantExperiences', '重要经历'),
      ('worldview', '世界观'),
    ],
    CharacterProfileSection.relationship: [
      ('relationship', '关系'),
      ('howMet', '相识'),
      ('currentStage', '当前阶段'),
    ],
  };

  List<(String, String)> get _fields => _definitions[widget.section]!;

  String get _title => switch (widget.section) {
    CharacterProfileSection.basic => '基础资料',
    CharacterProfileSection.appearance => '外貌设定',
    CharacterProfileSection.personality => '性格设定',
    CharacterProfileSection.background => '背景故事',
    CharacterProfileSection.relationship => '关系设定',
  };

  @override
  void initState() {
    super.initState();
    for (final field in _fields) {
      _controllers[field.$1] = TextEditingController();
    }
    _load();
  }

  Future<void> _load() async {
    final characters = await CharacterRegistryService().loadCharacters();
    final character = characters.firstWhere(
      (item) => item.id == widget.characterId,
      orElse: AiCharacter.placeholder,
    );
    final legacy = await CharacterSettingsStorageService(
      characterId: widget.characterId,
    ).loadSettings();
    final profile = await CharacterProfileStorageService(
      characterId: widget.characterId,
    ).load(character: character, legacySettings: legacy);
    final json = profile.toJson();
    for (final field in _fields) {
      _controllers[field.$1]!.text = json[field.$1]?.toString() ?? '';
    }
    if (!mounted) return;
    setState(() => _profile = profile);
  }

  Future<void> _save() async {
    final profile = _profile;
    if (profile == null || _saving) return;
    setState(() => _saving = true);
    final json = Map<String, dynamic>.from(profile.toJson());
    for (final field in _fields) {
      json[field.$1] = _controllers[field.$1]!.text.trim();
    }
    final updated = CharacterProfile.fromJson(json, widget.characterId);
    await CharacterProfileStorageService(
      characterId: widget.characterId,
    ).save(updated);
    if (!mounted) return;
    setState(() {
      _profile = updated;
      _saving = false;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('角色资料已保存')));
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
          title: Text(_title),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          actions: [
            TextButton(
              onPressed: _profile == null || _saving ? null : _save,
              child: Text(_saving ? '保存中' : '保存'),
            ),
          ],
        ),
        body: _profile == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: _fields.map((field) {
                        final longField = const {
                          'overallAppearance',
                          'personalityDescription',
                          'familyBackground',
                          'upbringing',
                          'importantExperiences',
                          'worldview',
                        }.contains(field.$1);
                        return TextField(
                          controller: _controllers[field.$1],
                          maxLines: longField ? 5 : 1,
                          maxLength: field.$1 == 'personalityDescription'
                              ? 500
                              : null,
                          decoration: InputDecoration(
                            labelText: field.$2,
                            border: InputBorder.none,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(8, 12, 8, 0),
                    child: Text(
                      '结构化资料会优先用于角色上下文，空字段仍可兼容旧版人设数据。',
                      style: TextStyle(color: Color(0xFF777777), fontSize: 12),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
