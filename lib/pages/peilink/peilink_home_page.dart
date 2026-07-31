import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'add_ai_page.dart';
import 'create_group_chat_page.dart';
import 'peilink_chats_page.dart';
import 'peilink_contacts_page.dart';
import 'peilink_me_page.dart';
import 'peilink_discover_page.dart';

class PeiLinkHomePage extends StatefulWidget {
  const PeiLinkHomePage({super.key});

  @override
  State<PeiLinkHomePage> createState() => _PeiLinkHomePageState();
}

class _PeiLinkHomePageState extends State<PeiLinkHomePage> {
  int _currentIndex = 0;

  static const _titles = ['PeiLink', '羁绊', '发现', '我'];

  int _contactsRevision = 0;
  int _chatsRevision = 0;

  List<Widget> get _pages => [
    PeiLinkChatsPage(key: ValueKey(_chatsRevision)),
    PeiLinkContactsPage(key: ValueKey(_contactsRevision)),
    const PeiLinkDiscoverPage(),
    const PeiLinkMePage(),
  ];

  Future<void> _showChatAddMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline_rounded),
              title: const Text('发起单聊'),
              onTap: () => Navigator.pop(context, 'single'),
            ),
            ListTile(
              leading: const Icon(Icons.group_add_outlined),
              title: const Text('创建群聊'),
              onTap: () => Navigator.pop(context, 'group'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'single') {
      setState(() => _currentIndex = 1);
      return;
    }
    final created = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateGroupChatPage()),
    );
    if (created != null && mounted) {
      setState(() => _chatsRevision += 1);
    }
  }

  Future<void> _openAddAi() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddAiPage()),
    );
    if (created == true && mounted) {
      setState(() => _contactsRevision += 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F4F4),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF4F4F4),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          title: Text(
            _titles[_currentIndex],
            style: const TextStyle(
              color: Color(0xFF171717),
              fontSize: 19,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            if (_currentIndex == 0)
              IconButton(
                onPressed: _showChatAddMenu,
                tooltip: '添加',
                icon: const Icon(
                  Icons.add_circle_outline_rounded,
                  color: Color(0xFF171717),
                  size: 27,
                ),
              ),
            if (_currentIndex == 1)
              IconButton(
                onPressed: _openAddAi,
                tooltip: '添加 AI',
                icon: const Icon(
                  Icons.person_add_alt_1_outlined,
                  color: Color(0xFF171717),
                  size: 27,
                ),
              ),
            const SizedBox(width: 4),
          ],
        ),
        body: IndexedStack(
          index: _currentIndex,
          children: _pages,
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          type: BottomNavigationBarType.fixed,
          backgroundColor: const Color(0xFFFAFAFA),
          selectedItemColor: const Color(0xFF4E8EAD),
          unselectedItemColor: const Color(0xFF171717),
          selectedFontSize: 12,
          unselectedFontSize: 12,
          onTap: (index) {
            setState(() => _currentIndex = index);
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline_rounded),
              activeIcon: Icon(Icons.chat_bubble_rounded),
              label: '消息',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_outline_rounded),
              activeIcon: Icon(Icons.people_rounded),
              label: '羁绊',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.explore_outlined),
              activeIcon: Icon(Icons.explore_rounded),
              label: '发现',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline_rounded),
              activeIcon: Icon(Icons.person_rounded),
              label: '我',
            ),
          ],
        ),
      ),
    );
  }
}
