import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/ai_character.dart';
import '../../models/echo_item.dart';
import '../../models/user_profile.dart';
import '../../services/character_registry_service.dart';
import '../../services/echo_image_storage_service.dart';
import '../../services/echo_profile_storage_service.dart';
import '../../services/echo_storage_service.dart';
import '../../services/user_profile_storage_service.dart';
import 'echo_compose_page.dart';
import 'echo_cover_editor_page.dart';
import 'echo_ai_draft_page.dart';
import 'echo_comments_page.dart';

class PeiLinkEchoPage extends StatefulWidget {
  const PeiLinkEchoPage({super.key, this.character});

  /// 为空时显示“我”的 Echo；传入角色时显示该角色的生活主页。
  final AiCharacter? character;

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
  bool _loading = true;

  bool get _isUserPage => widget.character == null;
  String get _ownerId => _isUserPage ? _userEchoId : _character!.id;
  String get _displayName =>
      _isUserPage ? _userProfile.nickname : _character!.characterName;
  String get _signature {
    if (_isUserPage) {
      final signature = _userProfile.signature.trim();
      return signature.isEmpty ? '这里记录我的生活。' : signature;
    }
    return '这里记录 ${_character!.characterName} 的生活。';
  }

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  Future<void> _loadPage() async {
    if (mounted) setState(() => _loading = true);
    try {
      final character =
          widget.character ?? await _registry.loadActiveCharacter();
      final userProfile = await UserProfileStorageService().loadProfile();
      final ownerId = _isUserPage ? _userEchoId : character.id;
      final results = await Future.wait<dynamic>([
        EchoStorageService(characterId: ownerId).loadItems(),
        EchoProfileStorageService(ownerId: ownerId).loadProfile(),
      ]);
      if (!mounted) return;
      setState(() {
        _character = character;
        _userProfile = userProfile;
        _items = results[0] as List<EchoItem>;
        _echoProfile = results[1] as EchoProfile;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('Echo 加载失败：$error');
    }
  }

  Future<void> _reloadTimeline() async {
    final items = await EchoStorageService(characterId: _ownerId).loadItems();
    if (!mounted) return;
    setState(() => _items = items);
  }

  AiCharacter _composeOwner() {
    if (!_isUserPage) return _character!;
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
    if (_isUserPage || _character == null) return;
    final published = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EchoAiDraftPage(character: _character!),
      ),
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
      await EchoStorageService(characterId: _ownerId).updateItem(updated);
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
    await EchoStorageService(characterId: _ownerId).deleteItem(item.id);
    await EchoImageStorageService(
      characterId: _ownerId,
    ).deleteImages(item.imagePaths);
    if (!mounted) return;
    setState(() => _items = _items.where((e) => e.id != item.id).toList());
  }

  Future<void> _openComments(EchoItem item) async {
    final updated = await Navigator.push<EchoItem>(
      context,
      MaterialPageRoute(
        builder: (_) => EchoCommentsPage(
          ownerId: _ownerId,
          echo: item,
          userProfile: _userProfile,
          character: _isUserPage ? null : _character,
        ),
      ),
    );
    if (updated != null) {
      await _reloadTimeline();
    } else {
      await _reloadTimeline();
    }
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
            : RefreshIndicator(
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
                        onChangeCover: _changeCover,
                      ),
                    ),
                    if (_items.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _QuietEmptyState(onCreate: _showCreateMenu),
                      )
                    else
                      SliverList.builder(
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return _TimelineItem(
                            avatar: _avatar(size: 46),
                            displayName: _displayName,
                            item: item,
                            onLike: () => _toggleLike(item),
                            onCollect: () => _toggleCollected(item),
                            onComment: () => _openComments(item),
                            onDelete: () => _deleteItem(item),
                          );
                        },
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 42)),
                  ],
                ),
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
    required this.onChangeCover,
  });

  final Widget cover;
  final Widget avatar;
  final String displayName;
  final String signature;
  final VoidCallback onBack;
  final VoidCallback onCreate;
  final VoidCallback onChangeCover;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 330,
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              cover,
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black38,
                      Colors.transparent,
                      Colors.black45,
                    ],
                  ),
                ),
              ),
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onChangeCover,
                    splashColor: Colors.white10,
                    highlightColor: Colors.transparent,
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
                top: MediaQuery.paddingOf(context).top + 2,
                right: 8,
                child: IconButton(
                  tooltip: '记录 Echo',
                  onPressed: onCreate,
                  icon: const Icon(Icons.camera_alt_rounded),
                  color: Colors.white,
                ),
              ),
              Positioned(
                right: 18,
                bottom: 18,
                child: Text(
                  displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                  ),
                ),
              ),
              Positioned(
                right: 18,
                bottom: -34,
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
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 45, 104, 18),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              signature,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF6E7780),
                fontSize: 13,
                height: 1.45,
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
                                            EchoAuthorType.character
                                        ? displayName
                                        : '我',
                                    style: const TextStyle(
                                      color: Color(0xFF576B95),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
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
