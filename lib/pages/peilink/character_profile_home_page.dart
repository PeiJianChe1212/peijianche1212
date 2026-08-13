import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/ai_character.dart';
import '../../models/character_archive.dart';
import '../../models/character_profile.dart';
import '../../services/character_archive_storage_service.dart';
import '../../services/character_profile_storage_service.dart';
import '../../services/character_settings_storage_service.dart';
import '../../services/character_prompt_preview_service.dart';
import '../../theme/app_theme_background.dart';
import 'character_profile_section_page.dart';
import 'character_archive_page.dart';

class CharacterProfileHomePage extends StatefulWidget {
  const CharacterProfileHomePage({super.key, required this.character});

  final AiCharacter character;

  @override
  State<CharacterProfileHomePage> createState() =>
      _CharacterProfileHomePageState();
}

class _CharacterProfileHomePageState extends State<CharacterProfileHomePage> {
  CharacterProfile? _profile;
  CharacterArchive? _archive;

  AiCharacter get character => widget.character;

  @override
  void initState() {
    super.initState();
    _loadCompletion();
  }

  Future<void> _loadCompletion() async {
    final legacy = await CharacterSettingsStorageService(
      characterId: character.id,
    ).loadSettings();
    final results = await Future.wait([
      CharacterProfileStorageService(
        characterId: character.id,
      ).load(character: character, legacySettings: legacy),
      CharacterArchiveStorageService(characterId: character.id).load(),
    ]);
    if (!mounted) return;
    setState(() {
      _profile = results[0] as CharacterProfile;
      _archive = results[1] as CharacterArchive;
    });
  }

  Future<void> _open(BuildContext context, Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    await _loadCompletion();
  }

  ImageProvider? get _avatar {
    final path = character.avatarPath.trim();
    if (path.isNotEmpty && File(path).existsSync()) {
      return FileImage(File(path));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ThemeBackgroundContainer(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('角色资料'),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          actions: [
            IconButton(
              tooltip: '预览最终 Prompt',
              onPressed: _showPromptPreview,
              icon: const Icon(Icons.visibility_outlined),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
          children: [
            Column(
              children: [
                CircleAvatar(
                  radius: 42,
                  backgroundColor: const Color(0xFFE5EBEE),
                  backgroundImage: _avatar,
                  child: _avatar == null
                      ? const Icon(Icons.auto_awesome_rounded, size: 34)
                      : null,
                ),
                const SizedBox(height: 10),
                Text(
                  character.displayName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  '角色资料',
                  style: TextStyle(color: Color(0xFF777777), fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _CompletionCard(profile: _profile, archive: _archive),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _tile(context, '基础资料', CharacterProfileSection.basic),
                  _tile(context, '外貌设定', CharacterProfileSection.appearance),
                  _tile(context, '性格设定', CharacterProfileSection.personality),
                  _tile(context, '背景故事', CharacterProfileSection.background),
                  _tile(context, '关系资料', CharacterProfileSection.relationship),
                  ListTile(
                    title: const Text('角色档案'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _open(
                      context,
                      CharacterArchivePage(
                        characterId: character.id,
                        characterName: character.displayName,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPromptPreview() async {
    final preview = await CharacterPromptPreviewService(
      character: character,
    ).build();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.86,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Row(
                  children: [
                    Icon(Icons.visibility_outlined),
                    SizedBox(width: 10),
                    Text(
                      '最终 Prompt 预览',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  '仅展示当前角色资料、档案、用户资料与 Memory 的组合结果。',
                  style: TextStyle(color: Colors.black54),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F5F7),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      preview,
                      style: const TextStyle(fontSize: 14, height: 1.55),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    String title,
    CharacterProfileSection section,
  ) {
    return ListTile(
      title: Text(title),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => _open(
        context,
        CharacterProfileSectionPage(
          characterId: character.id,
          section: section,
        ),
      ),
    );
  }
}

class _CompletionCard extends StatelessWidget {
  const _CompletionCard({required this.profile, required this.archive});

  final CharacterProfile? profile;
  final CharacterArchive? archive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('资料完成度', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          _CompletionRow(label: '基础资料', value: profile?.basicCompletion ?? 0),
          const SizedBox(height: 10),
          _CompletionRow(
            label: '外貌设定',
            value: profile?.appearanceCompletion ?? 0,
          ),
          const SizedBox(height: 10),
          _CompletionRow(label: '角色档案', value: archive?.completion ?? 0),
        ],
      ),
    );
  }
}

class _CompletionRow extends StatelessWidget {
  const _CompletionRow({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final percentage = (value * 100).round();
    return Row(
      children: [
        SizedBox(width: 76, child: Text(label)),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 7,
              backgroundColor: const Color(0xFFE8ECEE),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 36,
          child: Text('$percentage%', textAlign: TextAlign.right),
        ),
      ],
    );
  }
}
