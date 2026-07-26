import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/ai_character.dart';
import '../../services/character_registry_service.dart';
import 'character_detail_page.dart';

class PeiLinkContactsPage extends StatefulWidget {
  const PeiLinkContactsPage({super.key});

  @override
  State<PeiLinkContactsPage> createState() => _PeiLinkContactsPageState();
}

class _PeiLinkContactsPageState extends State<PeiLinkContactsPage> {
  final CharacterRegistryService _registry = CharacterRegistryService();

  List<AiCharacter> _characters = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final characters = await _registry.loadCharacters();
      characters.sort((a, b) {
        final initialCompare = _initialFor(a.characterName).compareTo(
          _initialFor(b.characterName),
        );
        if (initialCompare != 0) return initialCompare;
        return a.characterName.compareTo(b.characterName);
      });
      if (!mounted) return;
      setState(() {
        _characters = characters;
        _loading = false;
      });
    } catch (error) {
      debugPrint('加载角色列表失败：$error');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _openCharacter(AiCharacter character) async {
    await _registry.setActiveCharacter(character.id);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CharacterDetailPage(character: character)),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<AiCharacter>>{};
    for (final character in _characters) {
      groups.putIfAbsent(_initialFor(character.characterName), () => []).add(
        character,
      );
    }

    return Container(
      color: Colors.white,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final entry in groups.entries) ...[
                  _InitialHeader(initial: entry.key),
                  for (final character in entry.value)
                    _CharacterTile(
                      character: character,
                      onTap: () => _openCharacter(character),
                    ),
                ],
              ],
            ),
    );
  }
}

String _initialFor(String name) {
  final value = name.trim();
  if (value.isEmpty) return '#';
  final first = value.characters.first;
  final upper = first.toUpperCase();
  if (RegExp(r'[A-Z]').hasMatch(upper)) return upper;

  const commonSurnameInitials = <String, String>{
    '阿': 'A', '白': 'B', '包': 'B', '鲍': 'B', '毕': 'B', '卞': 'B',
    '蔡': 'C', '曹': 'C', '岑': 'C', '柴': 'C', '常': 'C', '车': 'C',
    '陈': 'C', '成': 'C', '程': 'C', '崔': 'C', '戴': 'D', '邓': 'D',
    '狄': 'D', '丁': 'D', '董': 'D', '窦': 'D', '杜': 'D', '段': 'D',
    '范': 'F', '方': 'F', '樊': 'F', '费': 'F', '冯': 'F', '傅': 'F',
    '高': 'G', '葛': 'G', '龚': 'G', '顾': 'G', '郭': 'G', '韩': 'H',
    '郝': 'H', '何': 'H', '贺': 'H', '洪': 'H', '胡': 'H', '花': 'H',
    '华': 'H', '黄': 'H', '霍': 'H', '纪': 'J', '季': 'J', '贾': 'J',
    '江': 'J', '姜': 'J', '蒋': 'J', '金': 'J', '孔': 'K', '赖': 'L',
    '蓝': 'L', '郎': 'L', '雷': 'L', '黎': 'L', '李': 'L', '连': 'L',
    '梁': 'L', '廖': 'L', '林': 'L', '凌': 'L', '刘': 'L', '柳': 'L',
    '龙': 'L', '陆': 'L', '罗': 'L', '吕': 'L', '马': 'M', '毛': 'M',
    '孟': 'M', '莫': 'M', '倪': 'N', '宁': 'N', '牛': 'N', '欧': 'O',
    '潘': 'P', '裴': 'P', '彭': 'P', '皮': 'P', '平': 'P', '齐': 'Q',
    '钱': 'Q', '乔': 'Q', '秦': 'Q', '邱': 'Q', '任': 'R', '沈': 'S',
    '施': 'S', '石': 'S', '史': 'S', '宋': 'S', '苏': 'S', '孙': 'S',
    '谭': 'T', '唐': 'T', '陶': 'T', '田': 'T', '童': 'T', '万': 'W',
    '汪': 'W', '王': 'W', '韦': 'W', '魏': 'W', '温': 'W', '吴': 'W',
    '伍': 'W', '武': 'W', '席': 'X', '夏': 'X', '萧': 'X', '谢': 'X',
    '辛': 'X', '熊': 'X', '徐': 'X', '许': 'X', '薛': 'X', '严': 'Y',
    '颜': 'Y', '杨': 'Y', '姚': 'Y', '叶': 'Y', '易': 'Y', '尹': 'Y',
    '袁': 'Y', '俞': 'Y', '余': 'Y', '于': 'Y', '虞': 'Y', '曾': 'Z',
    '翟': 'Z', '张': 'Z', '章': 'Z', '赵': 'Z', '郑': 'Z', '钟': 'Z',
    '周': 'Z', '朱': 'Z', '诸': 'Z', '庄': 'Z', '邹': 'Z', '左': 'Z',
  };
  return commonSurnameInitials[first] ?? '#';
}

class _InitialHeader extends StatelessWidget {
  const _InitialHeader({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF4F4F4),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Text(
        initial,
        style: const TextStyle(
          color: Color(0xFF888888),
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _CharacterTile extends StatelessWidget {
  const _CharacterTile({required this.character, required this.onTap});

  final AiCharacter character;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              _CharacterAvatar(character: character),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  character.characterName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CharacterAvatar extends StatelessWidget {
  const _CharacterAvatar({required this.character});

  final AiCharacter character;

  @override
  Widget build(BuildContext context) {
    final path = character.avatarPath.trim();
    if (path.isNotEmpty && File(path).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Image.file(File(path), width: 48, height: 48, fit: BoxFit.cover),
      );
    }
    if (character.isBuiltIn) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Image.asset(
          'assets/images/pei_avatar.jpg',
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          alignment: const Alignment(0, -0.15),
        ),
      );
    }
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFFE5EBEE),
        borderRadius: BorderRadius.circular(9),
      ),
      child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF647C8B)),
    );
  }
}
