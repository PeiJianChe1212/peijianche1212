import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/echo_item.dart';
import '../../services/character_registry_service.dart';
import '../../services/echo_storage_service.dart';
import 'peilink_echo_page.dart';

class PeiLinkDiscoverPage extends StatefulWidget {
  const PeiLinkDiscoverPage({super.key});

  @override
  State<PeiLinkDiscoverPage> createState() => _PeiLinkDiscoverPageState();
}

class _PeiLinkDiscoverPageState extends State<PeiLinkDiscoverPage> {
  List<EchoItem> _recentItems = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final characters = await CharacterRegistryService().loadCharacters();
    final ownerIds = <String>[
      'peilink_user_echo',
      ...characters.map((character) => character.id),
    ];
    final timelines = await Future.wait(
      ownerIds.map(
        (id) => EchoStorageService(characterId: id).loadItems(),
      ),
    );
    final items = timelines.expand((timeline) => timeline).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (!mounted) return;
    setState(() {
      _recentItems = items.take(3).toList();
      _loading = false;
    });
  }

  Future<void> _openEcho() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const PeiLinkEchoPage(showPublicTimeline: true),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF4F4F4),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(top: 10),
              children: [
                Material(
                  color: Colors.white,
                  child: InkWell(
                    onTap: _openEcho,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
                      child: Row(
                        children: [
                          const _EchoMark(),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Echo',
                                  style: TextStyle(
                                    color: Color(0xFF171717),
                                    fontSize: 17,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  '生活回声',
                                  style: TextStyle(
                                    color: Color(0xFF999999),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _EchoPreview(items: _recentItems),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: Color(0xFFB7B7B7),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Text(
                    '从这里进入公共 Echo。你和所有角色发布的生活回声都会汇总在这里。',
                    style: const TextStyle(
                      color: Color(0xFFAAAAAA),
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _EchoMark extends StatelessWidget {
  const _EchoMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6BA9C3), Color(0xFF476E91)],
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.waves_rounded, color: Colors.white, size: 23),
    );
  }
}

class _EchoPreview extends StatelessWidget {
  const _EchoPreview({required this.items});

  final List<EchoItem> items;

  @override
  Widget build(BuildContext context) {
    final imagePaths = items
        .expand((item) => item.imagePaths)
        .where((path) => path.trim().isNotEmpty && File(path).existsSync())
        .take(2)
        .toList();

    if (imagePaths.isEmpty) {
      if (items.isEmpty) return const SizedBox.shrink();
      return Container(
        constraints: const BoxConstraints(maxWidth: 100),
        child: Text(
          items.first.content,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.right,
          style: const TextStyle(color: Color(0xFF999999), fontSize: 12),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: imagePaths
          .map(
            (path) => Padding(
              padding: const EdgeInsets.only(left: 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Image.file(
                  File(path),
                  width: 42,
                  height: 42,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
