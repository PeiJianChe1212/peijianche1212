import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../services/pei_file_platform_service.dart';
import '../../services/pei_file_service.dart';
import '../../theme/app_theme_background.dart';

class CharacterImportPage extends StatefulWidget {
  const CharacterImportPage({super.key});

  @override
  State<CharacterImportPage> createState() => _CharacterImportPageState();
}

class _CharacterImportPageState extends State<CharacterImportPage> {
  final _fileService = PeiFileService();
  final _platform = const PeiFilePlatformService();
  PeiCharacterPackage? _package;
  String _fileName = '';
  String? _error;
  bool _busy = false;

  Future<void> _selectFile() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final selected = await _platform.pickFile();
      if (selected == null || !mounted) return;
      if (!selected.name.toLowerCase().endsWith('.pei')) {
        throw const PeiFileCorruptedException();
      }
      final parsed = _fileService.parse(selected.bytes);
      setState(() {
        _package = parsed;
        _fileName = selected.name;
      });
    } on PeiFileException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = const PeiFileCorruptedException().message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmImport() async {
    final package = _package;
    if (package == null || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await _fileService.importCharacter(package);
      if (!mounted) return;
      final suffix = result.renamed ? '（因重名已保存为 ）' : '';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('角色导入成功$suffix')));
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => _error = '导入失败，原有角色和数据未被修改。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ThemeBackgroundContainer(
    child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('导入 .pei 角色'),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          if (_package == null) _emptyState() else _preview(_package!),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEEF0),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xFFAA4250)),
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const ValueKey('select-pei-file'),
            onPressed: _busy ? null : _selectFile,
            icon: const Icon(Icons.file_open_rounded),
            label: Text(_package == null ? '选择 .pei 文件' : '重新选择文件'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8053D6),
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
          ),
          if (_package != null) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              key: const ValueKey('confirm-pei-import'),
              onPressed: _busy ? null : _confirmImport,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('确认创建角色'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF5968C7),
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ],
          const SizedBox(height: 14),
          const Text(
            '导入只会创建新角色，不会覆盖已有角色，也不会改动聊天、Echo、羁绊或记忆数据。',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF777185),
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _emptyState() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 38),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .68),
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: Colors.white),
    ),
    child: const Column(
      children: [
        Icon(Icons.folder_copy_rounded, size: 58, color: Color(0xFF8053D6)),
        SizedBox(height: 18),
        Text(
          '选择 PeiLink 角色文件',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 8),
        Text(
          '读取后会先展示角色预览，确认后才会创建。',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF727084)),
        ),
      ],
    ),
  );

  Widget _preview(PeiCharacterPackage package) {
    final character = package.character;
    return Container(
      key: const ValueKey('pei-character-preview'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .76),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipOval(child: _previewAvatar(package.avatarBytes)),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      character.characterName,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF858093),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            package.memory == null
                ? '纯角色文件：不包含记忆。'
                : '此文件包含私人记忆：经历 ${package.memory!.events.length} 条、用户记忆 ${package.memory!.users.length} 条、旧记忆 ${package.memory!.legacy.length} 条及记忆汇总。确认后仅写入新角色。',
          ),
          const SizedBox(height: 12),
          const Text('角色简介', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            character.introduction.trim().isEmpty
                ? '未填写简介'
                : character.introduction,
            style: const TextStyle(color: Color(0xFF666276), height: 1.5),
          ),
          const SizedBox(height: 16),
          const Text('基础设定', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            package.settings.coreProfile,
            maxLines: 7,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF666276), height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _previewAvatar(Uint8List? bytes) => Container(
    width: 72,
    height: 72,
    color: const Color(0xFFE8EAF5),
    child: bytes == null
        ? const Icon(
            Icons.auto_awesome_rounded,
            color: Color(0xFF6F78C5),
            size: 34,
          )
        : Image.memory(bytes, fit: BoxFit.cover),
  );
}
