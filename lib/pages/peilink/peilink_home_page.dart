import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/user_profile.dart';
import '../../services/user_profile_storage_service.dart';
import '../../theme/app_theme_background.dart';
import '../../theme/app_dimensions.dart';
import '../../theme/app_text_styles.dart';
import 'add_ai_page.dart';
import 'create_group_chat_page.dart';
import 'peilink_chats_page.dart';
import 'peilink_contacts_page.dart';
import 'peilink_echo_page.dart';
import 'peilink_profile_drawer.dart';

class PeiLinkHomePage extends StatefulWidget {
  const PeiLinkHomePage({super.key});

  @override
  State<PeiLinkHomePage> createState() => _PeiLinkHomePageState();
}

class _PeiLinkHomePageState extends State<PeiLinkHomePage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _profileStorage = UserProfileStorageService();

  int _currentIndex = 0;
  int _contactsRevision = 0;
  int _chatsRevision = 0;
  UserProfile _profile = const UserProfile();

  static const _titles = ['PeiLink', '羁绊', 'Echo'];

  List<Widget> get _pages => [
    PeiLinkChatsPage(key: ValueKey(_chatsRevision)),
    PeiLinkContactsPage(key: ValueKey(_contactsRevision)),
    const PeiLinkEchoPage(showPublicTimeline: true, embedded: true),
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await _profileStorage.loadProfile();
    if (!mounted) return;
    setState(() => _profile = profile);
  }

  Future<void> _showCreateMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_add_alt_1_outlined),
              title: const Text('创建 AI'),
              onTap: () => Navigator.pop(context, 'ai'),
            ),
            ListTile(
              leading: const Icon(Icons.group_add_outlined),
              title: const Text('新建群聊'),
              onTap: () => Navigator.pop(context, 'group'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'ai') {
      await _openAddAi();
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

  void _openRelationshipsFromDrawer() {
    Navigator.pop(context);
    setState(() => _currentIndex = 1);
  }

  @override
  Widget build(BuildContext context) {
    final avatarPath = _profile.avatarPath.trim();
    final avatarFile = avatarPath.isEmpty ? null : File(avatarPath);
    final hasAvatar = avatarFile?.existsSync() == true;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: ThemeBackgroundContainer(
        child: Scaffold(
          key: _scaffoldKey,
          extendBody: true,
          backgroundColor: Colors.transparent,
          drawer: PeiLinkProfileDrawer(
            onProfileChanged: (profile) {
              if (mounted) setState(() => _profile = profile);
            },
            onOpenRelationships: _openRelationshipsFromDrawer,
          ),
          appBar: AppBar(
            backgroundColor: const Color(0xEAF7F9FA),
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
            leadingWidth: 58,
            leading: Padding(
              padding: const EdgeInsets.only(left: 14, top: 7, bottom: 7),
              child: InkWell(
                key: const ValueKey('peilink-profile-entry'),
                borderRadius: BorderRadius.circular(AppDimensions.radiusPill),
                onTap: () => _scaffoldKey.currentState?.openDrawer(),
                child: ClipOval(
                  child: Container(
                    color: const Color(0xFFE3E7E9),
                    child: hasAvatar
                        ? Image.file(avatarFile!, fit: BoxFit.cover)
                        : const Icon(
                            Icons.person_rounded,
                            size: 24,
                            color: Color(0xFF7E8B92),
                          ),
                  ),
                ),
              ),
            ),
            title: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_titles[_currentIndex], style: AppTextStyles.pageTitle),
                const SizedBox(height: 1),
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome_rounded, size: 10),
                    SizedBox(width: 4),
                    Text(
                      'AI World · 已连接',
                      style: TextStyle(
                        color: Color(0xFF71828B),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              IconButton(
                key: const ValueKey('peilink-create-entry'),
                onPressed: _showCreateMenu,
                tooltip: '创建',
                icon: const Icon(
                  Icons.add_circle_outline_rounded,
                  color: Color(0xFF171717),
                  size: 25,
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: IndexedStack(index: _currentIndex, children: _pages),
          bottomNavigationBar: Padding(
            padding: EdgeInsets.fromLTRB(
              14,
              0,
              14,
              8 + MediaQuery.paddingOf(context).bottom,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.76),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.72),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x29152D3D),
                        blurRadius: 18,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    height: AppDimensions.bottomNavigationHeight,
                    child: BottomNavigationBar(
                      currentIndex: _currentIndex,
                      type: BottomNavigationBarType.fixed,
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      selectedItemColor: const Color(0xFF3E809D),
                      unselectedItemColor: const Color(0xFF536068),
                      selectedFontSize: 11,
                      unselectedFontSize: 11,
                      iconSize: AppDimensions.bottomNavigationIcon,
                      onTap: (index) => setState(() => _currentIndex = index),
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
                          icon: Icon(Icons.waves_outlined),
                          activeIcon: Icon(Icons.waves_rounded),
                          label: 'Echo',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
