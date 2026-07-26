import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/ai_character.dart';
import '../../models/character_settings.dart';
import '../../models/echo_item.dart';
import '../../services/character_registry_service.dart';
import '../../services/character_settings_storage_service.dart';
import '../../services/echo_storage_service.dart';
import '../chat_page.dart';
import 'character_management_page.dart';
import 'character_profile_edit_page.dart';
import 'peilink_echo_page.dart';

class CharacterDetailPage extends StatefulWidget {
  const CharacterDetailPage({super.key, this.character});

  final AiCharacter? character;

  @override
  State<CharacterDetailPage> createState() => _CharacterDetailPageState();
}

class _CharacterDetailPageState extends State<CharacterDetailPage> {
  final CharacterRegistryService _registry = CharacterRegistryService();

  CharacterSettings _settings = CharacterSettings.defaults();
  AiCharacter _character = AiCharacter.peiJianChe();
  List<EchoItem> _recentEcho = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final character = widget.character ?? await _registry.loadActiveCharacter();
    final settings = await CharacterSettingsStorageService(
      characterId: character.id,
    ).loadSettings();
    final echo = await EchoStorageService(characterId: character.id).loadItems();

    if (!mounted) return;
    setState(() {
      _character = character;
      _settings = settings;
      _recentEcho = echo.take(3).toList();
      _loading = false;
    });
  }

  Future<void> _openChat() async {
    await _registry.setActiveCharacter(_character.id);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChatPage()),
    );
    await _load();
  }

  Future<void> _openManagement() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CharacterManagementPage(characterId: _character.id),
      ),
    );
    if (!mounted) return;
    await _load();
  }

  Future<void> _openBasicProfile() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CharacterProfileEditPage(characterId: _character.id),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _openEcho() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PeiLinkEchoPage(character: _character)),
    );
    await _load();
  }

  Widget _avatar({double size = 76}) {
    final path = _character.avatarPath.trim();
    if (path.isNotEmpty && File(path).existsSync()) {
      return Image.file(File(path), width: size, height: size, fit: BoxFit.cover);
    }
    if (_character.isBuiltIn) {
      return Image.asset(
        'assets/images/pei_avatar.jpg',
        width: size,
        height: size,
        fit: BoxFit.cover,
        alignment: const Alignment(0, -0.15),
      );
    }
    return Container(
      width: size,
      height: size,
      color: const Color(0xFFE5EBEE),
      child: Icon(
        Icons.auto_awesome_rounded,
        size: size * 0.45,
        color: const Color(0xFF647C8B),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F4F4),
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: Text(
            _settings.displayName,
            style: const TextStyle(
              color: Color(0xFF171717),
              fontSize: 19,
              fontWeight: FontWeight.w600,
            ),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: '角色设置',
              onPressed: _loading ? null : _openManagement,
              icon: const Icon(Icons.more_horiz_rounded),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: EdgeInsets.zero,
                children: [
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: _avatar(),
                        ),
                        const SizedBox(width: 17),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _settings.displayName,
                                style: const TextStyle(
                                  color: Color(0xFF171717),
                                  fontSize: 22,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (_settings.remark.trim().isNotEmpty)
                                _ProfileLine(
                                  label: '本名',
                                  value: _settings.characterName,
                                ),
                              _ProfileLine(
                                label: 'PeiLink',
                                value: _character.peiLinkId.trim().isEmpty
                                    ? _character.id
                                    : _character.peiLinkId,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _InfoTile(
                    title: '朋友资料',
                    subtitle: '备注、生日、纪念日和角色基本信息',
                    onTap: _openBasicProfile,
                  ),
                  const SizedBox(height: 10),
                  _EchoTile(
                    displayName: _character.characterName,
                    items: _recentEcho,
                    onTap: _openEcho,
                  ),
                  const SizedBox(height: 10),
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '角色简介',
                          style: TextStyle(
                            color: Color(0xFF222222),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _settings.introduction.trim().isEmpty
                              ? '暂未填写'
                              : _settings.introduction.trim(),
                          style: TextStyle(
                            color: _settings.introduction.trim().isEmpty
                                ? const Color(0xFFAAAAAA)
                                : const Color(0xFF666666),
                            fontSize: 14,
                            height: 1.55,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: FilledButton.icon(
                      onPressed: _openChat,
                      icon: const Icon(Icons.chat_bubble_outline_rounded),
                      label: const Text('发消息'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF576B95),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ProfileLine extends StatelessWidget {
  const _ProfileLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Text(
        '$label：$value',
        style: const TextStyle(color: Color(0xFF777777), fontSize: 14),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 15, 14, 15),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 17)),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF999999),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFFB7B7B7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EchoTile extends StatelessWidget {
  const _EchoTile({
    required this.displayName,
    required this.items,
    required this.onTap,
  });

  final String displayName;
  final List<EchoItem> items;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final imagePaths = items
        .expand((item) => item.imagePaths)
        .where((path) => path.trim().isNotEmpty && File(path).existsSync())
        .take(3)
        .toList();

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 15, 14, 15),
          child: Row(
            children: [
              const SizedBox(
                width: 82,
                child: Text('Echo', style: TextStyle(fontSize: 17)),
              ),
              Expanded(
                child: imagePaths.isNotEmpty
                    ? Row(
                        children: imagePaths
                            .map(
                              (path) => Padding(
                                padding: const EdgeInsets.only(right: 5),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: Image.file(
                                    File(path),
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      )
                    : Text(
                        items.isEmpty ? '还没有生活回声' : items.first.content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF999999),
                          fontSize: 13,
                        ),
                      ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFFB7B7B7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
