import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/ai_character.dart';
import '../../models/echo_item.dart';
import '../../models/echo_comment.dart';
import '../../models/user_profile.dart';
import '../../services/character_registry_service.dart';
import '../../services/echo_image_storage_service.dart';
import '../../services/echo_profile_storage_service.dart';
import '../../services/echo_storage_service.dart';
import '../../services/user_profile_storage_service.dart';
import 'echo_compose_page.dart';
import 'echo_cover_editor_page.dart';
import 'echo_cover_preview_page.dart';
import 'echo_ai_draft_page.dart';
import 'echo_comments_page.dart';

class PeiLinkEchoPage extends StatefulWidget {
  const PeiLinkEchoPage({
    super.key,
    this.character,
    this.showPublicTimeline = false,
  });

  /// 传入角色时显示该角色的个人 Echo。
  /// character 为空且 showPublicTimeline 为 false 时，显示“我的 Echo”。
  final AiCharacter? character;

  /// 为 true 时显示所有角色与用户发布的公共 Echo 时间线。
  final bool showPublicTimeline;

  @override
  State<PeiLinkEchoPage> createState() => _PeiLinkEchoPageState();
}

class _PeiLinkEchoPageState extends State<PeiLinkEchoPage> {
  static const String _userEchoId = 'peilink_user_echo';

  final ImagePicker _imagePicker = ImagePicker();
  final CharacterRegistryService _registry = CharacterRegistryService();

  AiCharacter? _character;
  UserProfile _userProfile = const UserProfile();
  EchoProfile _echoProfile = const EchoProfile();
  List<EchoItem> _items = const [];
  List<AiCharacter> _characters = const [];
  bool _loading = true;
  int _spaceTabIndex = 0;

  bool get _isPublicTimeline => widget.showPublicTimeline;
  bool get _isUserPage => widget.character == null;
  bool get _isCharacterSpace => widget.character != null && !_isPublicTimeline;
  AiCharacter? get _spaceCharacter => _character ?? widget.character;
  String get _ownerId =>
      _isUserPage ? _userEchoId : (_spaceCharacter?.id ?? _userEchoId);
  String get _displayName => _isUserPage
      ? _userProfile.nickname
      : (_spaceCharacter?.characterName ?? '角色空间');
  String get _signature {
    if (_isUserPage) {
      final signature = _userProfile.signature.trim();
      return signature.isEmpty ? '这里记录我的生活。' : signature;
    }
    final character = _spaceCharacter;
    if (character == null) return '';
    final introduction = character.introduction.trim();
    return introduction.isEmpty
        ? '这里记录 ${character.characterName} 的生活。'
        : introduction;
  }

  @override
  void initState() {
    super.initState();
    _character = widget.character;
    _loadPage();
  }

  Future<void> _loadPage() async {
    if (mounted) setState(() => _loading = true);
    try {
      final character =
          widget.character ?? await _registry.loadActiveCharacter();
      final userProfile = await UserProfileStorageService().loadProfile();
      final characters = await _registry.loadCharacters();
      final ownerId = _isUserPage ? _userEchoId : character.id;

      final profile = await EchoProfileStorageService(
        ownerId: ownerId,
      ).loadProfile();

      List<EchoItem> items;
      if (_isPublicTimeline) {
        final ownerIds = <String>[
          _userEchoId,
          ...characters.map((item) => item.id),
        ];
        final timelines = await Future.wait(
          ownerIds.map((id) => EchoStorageService(characterId: id).loadItems()),
        );
        items = timelines.expand((timeline) => timeline).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      } else {
        items = await EchoStorageService(characterId: ownerId).loadItems();
      }

      if (!mounted) return;
      setState(() {
        _character = character;
        _characters = characters;
        _userProfile = userProfile;
        _items = items;
        _echoProfile = profile;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _character ??= widget.character;
        _loading = false;
      });
      _showMessage('Echo 加载失败：$error');
    }
  }

  Future<void> _reloadTimeline() async {
    if (_isPublicTimeline) {
      await _loadPage();
      return;
    }
    final items = await EchoStorageService(characterId: _ownerId).loadItems();
    if (!mounted) return;
    setState(() => _items = items);
  }

  AiCharacter _composeOwner() {
    final character = _spaceCharacter;
    if (!_isUserPage && character != null) return character;
    return AiCharacter(
      id: _userEchoId,
      characterName: _userProfile.nickname,
      remark: '',
      avatarPath: _userProfile.avatarPath,
      relationship: _userProfile.identity,
      createdAt: DateTime.now(),
    );
  }

  Future<void> _openCompose() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EchoComposePage(
          character: _composeOwner(),
          ownerLabel: _isUserPage ? '自己' : _displayName,
          isUserEcho: _isUserPage,
        ),
      ),
    );
    if (created == true) await _reloadTimeline();
  }

  Future<void> _openAiDraft() async {
    final character = _spaceCharacter;
    if (_isUserPage || character == null) return;
    final published = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => EchoAiDraftPage(character: character)),
    );
    if (published == true) await _reloadTimeline();
  }

  Future<void> _showCreateMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(_isUserPage ? '记录我的 Echo' : '记录 Echo'),
                onTap: () => Navigator.pop(sheetContext, 'compose'),
              ),
              if (!_isUserPage)
                ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('让角色生成 Echo'),
                  onTap: () => Navigator.pop(sheetContext, 'generate'),
                ),
            ],
          ),
        ),
      ),
    );
    if (action == 'compose') await _openCompose();
    if (action == 'generate') await _openAiDraft();
  }

  Future<void> _changeCover() async {
    try {
      final result = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
        maxWidth: 2600,
      );
      if (result == null || !mounted) return;

      final bytes = await Navigator.push<Uint8List>(
        context,
        MaterialPageRoute(
          builder: (_) => EchoCoverEditorPage(imagePath: result.path),
        ),
      );
      if (bytes == null) return;

      final service = EchoProfileStorageService(ownerId: _ownerId);
      final path = await service.saveCoverBytes(bytes);
      final updated = _echoProfile.copyWith(coverPath: path);
      await service.saveProfile(updated);
      if (!mounted) return;
      setState(() => _echoProfile = updated);
    } catch (error) {
      _showMessage('更换封面失败：$error');
    }
  }

  Future<void> _openCoverPreview() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => EchoCoverPreviewPage(
          coverPath: _echoProfile.coverPath,
          onChangeCover: _changeCover,
        ),
      ),
    );
    if (!mounted) return;
    final profile = await EchoProfileStorageService(
      ownerId: _ownerId,
    ).loadProfile();
    if (mounted) setState(() => _echoProfile = profile);
  }

  Future<void> _toggleLike(EchoItem item) async {
    final liked = !item.isLiked;
    await _replaceItem(
      item.copyWith(
        isLiked: liked,
        likeCount: liked
            ? item.likeCount + 1
            : item.likeCount > 0
            ? item.likeCount - 1
            : 0,
      ),
    );
  }

  Future<void> _toggleCollected(EchoItem item) async {
    await _replaceItem(item.copyWith(isCollected: !item.isCollected));
  }

  Future<void> _replaceItem(EchoItem updated) async {
    final index = _items.indexWhere((item) => item.id == updated.id);
    if (index < 0) return;
    final next = [..._items]..[index] = updated;
    setState(() => _items = next);
    try {
      await EchoStorageService(
        characterId: updated.characterId,
      ).updateItem(updated);
    } catch (error) {
      await _reloadTimeline();
      _showMessage('保存失败：$error');
    }
  }

  Future<void> _deleteItem(EchoItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这条 Echo？'),
        content: const Text('删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await EchoStorageService(characterId: item.characterId).deleteItem(item.id);
    await EchoImageStorageService(
      characterId: item.characterId,
    ).deleteImages(item.imagePaths);
    if (!mounted) return;
    setState(() => _items = _items.where((e) => e.id != item.id).toList());
  }

  Future<void> _openComments(EchoItem item) async {
    final updated = await Navigator.push<EchoItem>(
      context,
      MaterialPageRoute(
        builder: (_) => EchoCommentsPage(
          ownerId: item.characterId,
          echo: item,
          userProfile: _userProfile,
          character: _characterForItem(item),
        ),
      ),
    );
    if (updated != null) {
      await _reloadTimeline();
    } else {
      await _reloadTimeline();
    }
  }

  AiCharacter? _characterForItem(EchoItem item) {
    if (item.characterId == _userEchoId) return null;
    for (final character in _characters) {
      if (character.id == item.characterId) return character;
    }
    if (_character?.id == item.characterId) return _character;
    return null;
  }

  String _displayNameForItem(EchoItem item) {
    if (item.characterId == _userEchoId) return _userProfile.nickname;
    return _characterForItem(item)?.characterName ?? '未知角色';
  }

  Widget _avatarForItem(EchoItem item, {double size = 46}) {
    if (item.characterId == _userEchoId) {
      final path = _userProfile.avatarPath.trim();
      if (path.isNotEmpty && File(path).existsSync()) {
        return Image.file(
          File(path),
          width: size,
          height: size,
          fit: BoxFit.cover,
        );
      }
      return Container(
        width: size,
        height: size,
        color: const Color(0xFFE6EAED),
        child: Icon(
          Icons.person_rounded,
          size: size * 0.45,
          color: const Color(0xFF6F7D86),
        ),
      );
    }

    final character = _characterForItem(item);
    final path = character?.avatarPath.trim() ?? '';
    if (path.isNotEmpty && File(path).existsSync()) {
      return Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
      );
    }
    if (character?.isBuiltIn == true) {
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
      color: const Color(0xFFE6EAED),
      child: Icon(
        Icons.auto_awesome_rounded,
        size: size * 0.45,
        color: const Color(0xFF6F7D86),
      ),
    );
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _avatar({double size = 66}) {
    final path = _isUserPage
        ? _userProfile.avatarPath.trim()
        : (_character?.avatarPath.trim() ?? '');
    if (path.isNotEmpty && File(path).existsSync()) {
      return Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
      );
    }
    if (!_isUserPage && _character?.isBuiltIn == true) {
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
      color: const Color(0xFFE6EAED),
      child: Icon(
        _isUserPage ? Icons.person_rounded : Icons.auto_awesome_rounded,
        size: size * 0.45,
        color: const Color(0xFF6F7D86),
      ),
    );
  }

  Widget _cover() {
    final path = _echoProfile.coverPath.trim();
    if (path.isNotEmpty && File(path).existsSync()) {
      return Image.file(File(path), fit: BoxFit.cover);
    }
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7E98A5), Color(0xFFB8C6CB), Color(0xFF607985)],
        ),
      ),
      child: const Center(
        child: Icon(Icons.waves_rounded, size: 58, color: Colors.white70),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _isCharacterSpace
            ? _buildCharacterSpace()
            : _buildClassicEcho(),
      ),
    );
  }

  Widget _buildClassicEcho() {
    return RefreshIndicator(
      onRefresh: _reloadTimeline,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _EchoLifeHeader(
              cover: _cover(),
              avatar: _avatar(),
              displayName: _displayName,
              signature: _signature,
              onBack: () => Navigator.maybePop(context),
              onCreate: _showCreateMenu,
              onOpenCover: _openCoverPreview,
            ),
          ),
          if (_items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _QuietEmptyState(onCreate: _showCreateMenu),
            )
          else
            _timelineSliver(),
          const SliverToBoxAdapter(child: SizedBox(height: 42)),
        ],
      ),
    );
  }

  Widget _buildCharacterSpace() {
    return RefreshIndicator(
      onRefresh: _reloadTimeline,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _CharacterSpaceHeader(
              cover: _cover(),
              avatar: _avatar(size: 92),
              displayName: _displayName,
              signature: _signature,
              relationship: _spaceCharacter?.relationship.trim() ?? '',
              onBack: () => Navigator.maybePop(context),
              onCreate: _showCreateMenu,
              onOpenCover: _openCoverPreview,
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _CharacterSpaceTabHeader(
              currentIndex: _spaceTabIndex,
              onChanged: (index) => setState(() => _spaceTabIndex = index),
            ),
          ),
          if (_spaceTabIndex == 0) ...[
            if (_items.isEmpty)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 300,
                  child: _QuietEmptyState(onCreate: _showCreateMenu),
                ),
              )
            else
              _timelineSliver(),
          ] else
            SliverToBoxAdapter(
              child: SizedBox(
                height: 300,
                child: _SpacePlaceholder(index: _spaceTabIndex),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 42)),
        ],
      ),
    );
  }

  SliverList _timelineSliver() {
    return SliverList.builder(
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        return _TimelineItem(
          avatar: _avatarForItem(item),
          displayName: _displayNameForItem(item),
          item: item,
          onLike: () => _toggleLike(item),
          onCollect: () => _toggleCollected(item),
          onComment: () => _openComments(item),
          onDelete: () => _deleteItem(item),
        );
      },
    );
  }
}

class _CharacterSpaceHeader extends StatelessWidget {
  const _CharacterSpaceHeader({
    required this.cover,
    required this.avatar,
    required this.displayName,
    required this.signature,
    required this.relationship,
    required this.onBack,
    required this.onCreate,
    required this.onOpenCover,
  });

  final Widget cover;
  final Widget avatar;
  final String displayName;
  final String signature;
  final String relationship;
  final VoidCallback onBack;
  final VoidCallback onCreate;
  final VoidCallback onOpenCover;

  String? get _relationshipLabel {
    const emptyValues = {'', '未设置', '暂未设置', '未填写'};
    return emptyValues.contains(relationship) ? null : relationship;
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: Column(
        children: [
          SizedBox(
            height: 238,
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(onTap: onOpenCover, child: cover),
                ),
                const IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x66000000),
                          Colors.transparent,
                          Color(0x52000000),
                        ],
                        stops: [0, 0.52, 1],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 5,
                  left: 9,
                  child: _SpaceRoundButton(
                    tooltip: '返回',
                    icon: Icons.arrow_back_ios_new_rounded,
                    onTap: onBack,
                  ),
                ),
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 5,
                  right: 9,
                  child: _SpaceRoundButton(
                    tooltip: '发布 Echo',
                    icon: Icons.add_rounded,
                    onTap: onCreate,
                  ),
                ),
                Positioned(
                  left: 22,
                  bottom: -44,
                  child: Container(
                    width: 96,
                    height: 96,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.16),
                          blurRadius: 18,
                          offset: const Offset(0, 7),
                        ),
                      ],
                    ),
                    child: ClipOval(child: avatar),
                  ),
                ),
                const Positioned(
                  left: 132,
                  bottom: 14,
                  child: Text(
                    'PEILINK SPACE',
                    style: TextStyle(
                      color: Color(0xCFFFFFFF),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 7)],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(132, 13, 20, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF1B2028),
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  if (_relationshipLabel case final label?) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF2F7),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF64849A),
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(132, 5, 20, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                signature,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF7B838C),
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: _SpaceFutureMetric(
                    icon: Icons.favorite_border_rounded,
                    label: '好感度',
                  ),
                ),
                Expanded(
                  child: _SpaceFutureMetric(
                    icon: Icons.card_giftcard_rounded,
                    label: '礼物',
                  ),
                ),
                Expanded(
                  child: _SpaceFutureMetric(
                    icon: Icons.event_outlined,
                    label: '纪念日',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SpaceRoundButton extends StatelessWidget {
  const _SpaceRoundButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.22),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}

class _SpaceFutureMetric extends StatelessWidget {
  const _SpaceFutureMetric({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF91A5B2), size: 19),
        const SizedBox(height: 5),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF8A929A), fontSize: 10.5),
        ),
        const SizedBox(height: 2),
        const Text(
          '敬请期待',
          style: TextStyle(color: Color(0xFFC2C7CB), fontSize: 8.5),
        ),
      ],
    );
  }
}

class _CharacterSpaceTabHeader extends SliverPersistentHeaderDelegate {
  const _CharacterSpaceTabHeader({
    required this.currentIndex,
    required this.onChanged,
  });

  static const _labels = ['动态', '相册', '回忆', '关系'];

  final int currentIndex;
  final ValueChanged<int> onChanged;

  @override
  double get minExtent => 52;

  @override
  double get maxExtent => 52;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox.expand(
      child: Material(
        color: Colors.white,
        elevation: overlapsContent ? 2 : 0,
        shadowColor: Colors.black12,
        child: Row(
          children: List.generate(_labels.length, (index) {
            final selected = currentIndex == index;
            return Expanded(
              child: InkWell(
                onTap: () => onChanged(index),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      _labels[index],
                      style: TextStyle(
                        color: selected
                            ? const Color(0xFF26343D)
                            : const Color(0xFF8E969D),
                        fontSize: 14,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    if (selected)
                      const Positioned(
                        bottom: 0,
                        child: SizedBox(
                          width: 24,
                          height: 3,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Color(0xFF6E9AB2),
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(3),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _CharacterSpaceTabHeader oldDelegate) {
    return oldDelegate.currentIndex != currentIndex;
  }
}

class _SpacePlaceholder extends StatelessWidget {
  const _SpacePlaceholder({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    const labels = ['动态', '相册', '回忆', '关系'];
    const icons = [
      Icons.dynamic_feed_outlined,
      Icons.photo_library_outlined,
      Icons.auto_stories_outlined,
      Icons.hub_outlined,
    ];
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 76),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: const BoxDecoration(
                color: Color(0xFFF1F5F7),
                shape: BoxShape.circle,
              ),
              child: Icon(icons[index], color: const Color(0xFF91A8B5)),
            ),
            const SizedBox(height: 13),
            Text(
              '${labels[index]}空间已预留',
              style: const TextStyle(
                color: Color(0xFF6F7880),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              '未来会有新的生活内容住进这里',
              style: TextStyle(color: Color(0xFFB0B6BB), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _EchoLifeHeader extends StatelessWidget {
  const _EchoLifeHeader({
    required this.cover,
    required this.avatar,
    required this.displayName,
    required this.signature,
    required this.onBack,
    required this.onCreate,
    required this.onOpenCover,
  });

  final Widget cover;
  final Widget avatar;
  final String displayName;
  final String signature;
  final VoidCallback onBack;
  final VoidCallback onCreate;
  final VoidCallback onOpenCover;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 350,
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(onTap: onOpenCover, child: cover),
              ),
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black38,
                        Colors.transparent,
                        Colors.black38,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.paddingOf(context).top + 4,
                left: 6,
                child: IconButton(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  color: Colors.white,
                ),
              ),
              Positioned(
                top: MediaQuery.paddingOf(context).top + 4,
                right: 6,
                child: IconButton(
                  tooltip: '发布 Echo',
                  onPressed: onCreate,
                  icon: const Icon(Icons.camera_alt_rounded),
                  color: Colors.white,
                ),
              ),
              Positioned(
                right: 18,
                bottom: -42,
                child: Container(
                  width: 76,
                  height: 76,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: avatar,
                  ),
                ),
              ),
              Positioned(
                right: 106,
                bottom: 12,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 54, 106, 18),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              signature,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF6E7780),
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ),
        const Divider(height: 1, color: Color(0xFFEDEDED)),
      ],
    );
  }
}

class _QuietEmptyState extends StatelessWidget {
  const _QuietEmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onCreate,
      child: const Center(
        child: Padding(
          padding: EdgeInsets.only(bottom: 80),
          child: Text(
            '这里还没有留下任何回声。',
            style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 14),
          ),
        ),
      ),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.avatar,
    required this.displayName,
    required this.item,
    required this.onLike,
    required this.onCollect,
    required this.onComment,
    required this.onDelete,
  });

  final Widget avatar;
  final String displayName;
  final EchoItem item;
  final VoidCallback onLike;
  final VoidCallback onCollect;
  final VoidCallback onComment;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 12, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEDEDED))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(5), child: avatar),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    color: Color(0xFF576B95),
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                if (item.content.trim().isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    item.content,
                    style: const TextStyle(
                      color: Color(0xFF202020),
                      fontSize: 15,
                      height: 1.48,
                    ),
                  ),
                ],
                if (item.imagePaths.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _EchoImage(path: item.imagePaths.first),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      _formatTime(item.createdAt),
                      style: const TextStyle(
                        color: Color(0xFFAAAAAA),
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    PopupMenuButton<String>(
                      tooltip: '互动',
                      color: const Color(0xFF4C5157),
                      icon: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(
                          Icons.more_horiz_rounded,
                          size: 18,
                          color: Color(0xFF576B95),
                        ),
                      ),
                      onSelected: (value) {
                        if (value == 'like') onLike();
                        if (value == 'comment') onComment();
                        if (value == 'collect') onCollect();
                        if (value == 'delete') onDelete();
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'like',
                          child: Text(
                            item.isLiked ? '取消喜欢' : '喜欢',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'comment',
                          child: Text(
                            '评论',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'collect',
                          child: Text(
                            item.isCollected ? '取消收藏' : '收藏',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            '删除',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (item.likeCount > 0 || item.comments.isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 7),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    color: const Color(0xFFF3F4F6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (item.likeCount > 0)
                          Text(
                            '♡ ${item.likeCount}',
                            style: const TextStyle(
                              color: Color(0xFF576B95),
                              fontSize: 13,
                            ),
                          ),
                        for (final comment in item.comments)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text:
                                        comment.authorType ==
                                            EchoCommentAuthorType.character
                                        ? (comment.authorNameSnapshot
                                                  .trim()
                                                  .isEmpty
                                              ? displayName
                                              : comment.authorNameSnapshot
                                                    .trim())
                                        : '我',
                                    style: const TextStyle(
                                      color: Color(0xFF576B95),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (comment.replyToAuthorNameSnapshot
                                      .trim()
                                      .isNotEmpty) ...[
                                    const TextSpan(text: ' 回复 '),
                                    TextSpan(
                                      text: comment.replyToAuthorNameSnapshot
                                          .trim(),
                                      style: const TextStyle(
                                        color: Color(0xFF576B95),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                  const TextSpan(text: '：'),
                                  TextSpan(text: comment.content),
                                ],
                              ),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EchoImage extends StatelessWidget {
  const _EchoImage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: file.existsSync()
          ? Image.file(file, width: 230, height: 230, fit: BoxFit.cover)
          : Container(
              width: 230,
              height: 150,
              color: const Color(0xFFF0F0F0),
              alignment: Alignment.center,
              child: const Text('图片已不存在'),
            ),
    );
  }
}

String _formatTime(DateTime time) {
  final now = DateTime.now();
  final difference = now.difference(time);
  if (difference.inMinutes < 1) return '刚刚';
  if (difference.inMinutes < 60) return '${difference.inMinutes}分钟前';
  if (difference.inHours < 24) return '${difference.inHours}小时前';
  if (difference.inDays == 1) return '昨天';
  if (time.year == now.year) return '${time.month}月${time.day}日';
  return '${time.year}年${time.month}月${time.day}日';
}
