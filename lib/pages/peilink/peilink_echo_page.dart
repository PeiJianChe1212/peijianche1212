import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/ai_character.dart';
import '../../models/character_settings.dart';
import '../../models/chat_message.dart';
import '../../models/echo_item.dart';
import '../../models/echo_comment.dart';
import '../../models/echo_interaction_stats.dart';
import '../../models/echo_space_summary.dart';
import '../../models/relationship_growth.dart';
import '../../models/echo_visitor_record.dart';
import '../../models/shared_experience.dart';
import '../../models/user_profile.dart';
import '../../services/character_registry_service.dart';
import '../../services/character_settings_storage_service.dart';
import '../../services/chat_storage_service.dart';
import '../../services/echo_image_storage_service.dart';
import '../../services/echo_album_service.dart';
import '../../services/echo_comment_preview_service.dart';
import '../../services/echo_comment_author_service.dart';
import '../../services/echo_identity.dart';
import '../../services/echo_interaction_stats_service.dart';
import '../../services/echo_profile_storage_service.dart';
import '../../services/echo_space_decoration_storage_service.dart';
import 'echo_space_decoration_page.dart';
import '../../services/echo_storage_service.dart';
import '../../services/echo_visitor_storage_service.dart';
import '../../services/echo_visitor_social_service.dart';
import '../../services/shared_experience_storage_service.dart';
import '../../services/relationship_growth_service.dart';
import '../../services/user_profile_storage_service.dart';
import '../../theme/app_theme_background.dart';
import '../../widgets/echo/echo_interaction_bar.dart';
import '../../widgets/echo/echo_space_overview.dart';
import '../../widgets/echo/ai_verified_badge.dart';
import '../../widgets/echo/echo_visitor_card.dart';
import 'echo_compose_page.dart';
import 'relationship_gift_page.dart';
import 'relationship_growth_page.dart';
import 'echo_visitor_list_page.dart';
import 'echo_ai_draft_page.dart';
import 'echo_comments_page.dart';
import 'widgets/relationship_space_widgets.dart';

class PeiLinkEchoPage extends StatefulWidget {
  const PeiLinkEchoPage({
    super.key,
    this.character,
    this.showPublicTimeline = false,
    this.embedded = false,
  });

  /// 传入角色时显示该角色的个人 Echo。
  /// character 为空且 showPublicTimeline 为 false 时，显示“我的 Echo”。
  final AiCharacter? character;

  /// 为 true 时显示所有角色与用户发布的公共 Echo 时间线。
  final bool showPublicTimeline;

  /// 嵌入 PeiLink 一级 Tab 时不显示返回入口。
  final bool embedded;

  @override
  State<PeiLinkEchoPage> createState() => _PeiLinkEchoPageState();
}

class _PeiLinkEchoPageState extends State<PeiLinkEchoPage> {
  static const String _userEchoId = EchoIdentity.userEchoOwnerId;

  final CharacterRegistryService _registry = CharacterRegistryService();

  AiCharacter? _character;
  UserProfile _userProfile = const UserProfile();
  EchoProfile _echoProfile = const EchoProfile();
  EchoSpaceDecorationConfig _spaceDecoration =
      const EchoSpaceDecorationConfig();
  CharacterSettings? _characterSettings;
  List<EchoItem> _items = const [];
  List<SharedExperience> _memories = const [];
  Map<String, EchoInteractionStats> _interactionStats = const {};
  List<EchoVisitorRecord> _visitors = const [];
  List<AiCharacter> _characters = const [];
  bool _loading = true;
  bool _memoriesLoadFailed = false;
  bool _decorationLoadFailed = false;
  int _spaceTabIndex = 0;
  int _chatInteractionCount = 0;
  RelationshipGrowthProfile? _growthProfile;

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
    return echoSignatureText(_echoProfile);
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
      final userProfile = await UserProfileStorageService().loadProfile();
      final characters = await _registry.loadCharacters();
      final character =
          widget.character ??
          AiCharacter(
            id: _userEchoId,
            characterName: userProfile.nickname,
            remark: '',
            relationship: userProfile.identity,
            avatarPath: userProfile.avatarPath,
            createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          );
      final ownerId = _isUserPage ? _userEchoId : character.id;

      final profile = await EchoProfileStorageService(
        ownerId: ownerId,
      ).loadProfile();

      List<EchoItem> items;
      if (_isPublicTimeline) {
        final storedOwnerIds =
            await EchoStorageService.discoverStoredOwnerIds();
        final ownerIds = <String>{
          _userEchoId,
          ...characters.map((item) => item.id),
          ...storedOwnerIds,
        };
        final timelines = await Future.wait(
          ownerIds.map((id) => EchoStorageService(characterId: id).loadItems()),
        );
        items = timelines.expand((timeline) => timeline).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      } else {
        items = await EchoStorageService(characterId: ownerId).loadItems();
      }

      var memories = <SharedExperience>[];
      var memoriesLoadFailed = false;
      if (_isCharacterSpace) {
        try {
          memories = await SharedExperienceStorageService().loadForCharacter(
            character.id,
          );
        } catch (_) {
          memoriesLoadFailed = true;
        }
      }

      var decoration = const EchoSpaceDecorationConfig();
      var decorationLoadFailed = false;
      if (_isCharacterSpace) {
        try {
          decoration = await EchoSpaceDecorationStorageService(
            characterId: character.id,
          ).load();
        } catch (_) {
          decorationLoadFailed = true;
        }
      }

      CharacterSettings? characterSettings;
      var chatInteractionCount = 0;
      var chatMessages = <ChatMessage>[];
      RelationshipGrowthProfile? growthProfile;
      if (_isCharacterSpace) {
        try {
          characterSettings = await CharacterSettingsStorageService(
            characterId: character.id,
          ).loadSettings();
        } catch (_) {
          characterSettings = null;
        }
        try {
          chatMessages = await ChatStorageService(
            characterId: character.id,
          ).loadMessages();
          chatInteractionCount = chatMessages
              .where(
                (message) =>
                    !message.isRecalled && message.type != MessageType.system,
              )
              .length;
        } catch (_) {
          chatInteractionCount = 0;
        }
      }

      var interactionStats = <String, EchoInteractionStats>{};
      var visitors = <EchoVisitorRecord>[];
      if (!_isPublicTimeline) {
        final settingsRelation = characterSettings?.relation.trim() ?? '';
        final relation = settingsRelation.isNotEmpty
            ? settingsRelation
            : character.relationship.trim();
        interactionStats = await EchoInteractionStatsService(
          ownerId: ownerId,
        ).loadOrCreate(items, hasRelationship: relation.isNotEmpty);
        if (_isCharacterSpace) {
          visitors = await EchoVisitorStorageService(ownerId: ownerId)
              .recordDailyVisit(
                visitorId: _userEchoId,
                visitorName: userProfile.nickname,
                visitorAvatarPath: userProfile.avatarPath,
              );
          visitors = await const EchoVisitorSocialService().synchronize(
            owner: character,
            characters: characters,
          );
          growthProfile =
              await RelationshipGrowthService(
                characterId: character.id,
              ).synchronize(
                messages: chatMessages,
                echoes: items,
                metAt: character.createdAt,
              );
        } else {
          visitors = await EchoVisitorStorageService(ownerId: ownerId).load();
        }
      }

      if (!mounted) return;
      setState(() {
        _character = character;
        _characters = characters;
        _userProfile = userProfile;
        _items = items;
        _memories = memories;
        _interactionStats = interactionStats;
        _visitors = visitors;
        _memoriesLoadFailed = memoriesLoadFailed;
        _spaceDecoration = decoration;
        _characterSettings = characterSettings;
        _chatInteractionCount = chatInteractionCount;
        _growthProfile = growthProfile;
        _decorationLoadFailed = decorationLoadFailed;
        _echoProfile = profile;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _character ??= widget.character;
        _loading = false;
      });
      debugPrint('Echo 加载失败：$error');
      _showMessage('Echo 加载失败，请稍后再试');
    }
  }

  Future<void> _reloadTimeline() async {
    if (_isPublicTimeline) {
      await _loadPage();
      return;
    }
    final items = await EchoStorageService(characterId: _ownerId).loadItems();
    final settingsRelation = _characterSettings?.relation.trim() ?? '';
    final characterRelation = _spaceCharacter?.relationship.trim() ?? '';
    final interactionStats = _isCharacterSpace
        ? await EchoInteractionStatsService(ownerId: _ownerId).loadOrCreate(
            items,
            hasRelationship:
                settingsRelation.isNotEmpty || characterRelation.isNotEmpty,
          )
        : _interactionStats;
    if (!mounted) return;
    setState(() {
      _items = items;
      _interactionStats = interactionStats;
    });
  }

  AiCharacter _composeOwner() {
    final character = _spaceCharacter;
    if (!_isUserPage && character != null) return character;
    return userEchoOwner(_userProfile);
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

  /// Public feed entry: open the current user's own Echo space.
  Future<void> _openMyEchoSpace() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const PeiLinkEchoPage()),
    );
    if (mounted) await _reloadTimeline();
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
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
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
      ),
    );
    if (action == 'compose') await _openCompose();
    if (action == 'generate') await _openAiDraft();
  }

  Future<void> _showSpaceMoreMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('空间装扮'),
                  subtitle: _decorationLoadFailed
                      ? const Text('当前使用默认装扮')
                      : null,
                  onTap: () => Navigator.pop(sheetContext, 'decoration'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.music_note_rounded),
                  title: const Text('背景音乐'),
                  trailing: const Text('敬请期待'),
                  onTap: () => Navigator.pop(sheetContext, 'music'),
                ),
                ListTile(
                  leading: const Icon(Icons.favorite_outline_rounded),
                  title: const Text('关系设置'),
                  trailing: const Text('敬请期待'),
                  onTap: () => Navigator.pop(sheetContext, 'relationship'),
                ),
                ListTile(
                  leading: const Icon(Icons.people_outline_rounded),
                  title: const Text('访客设置'),
                  trailing: const Text('敬请期待'),
                  onTap: () => Navigator.pop(sheetContext, 'visitors'),
                ),
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('空间资料'),
                  trailing: const Text('敬请期待'),
                  onTap: () => Navigator.pop(sheetContext, 'profile'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'decoration') {
      final character = _spaceCharacter;
      if (character == null) return;
      final updated = await Navigator.push<EchoSpaceDecorationConfig>(
        context,
        MaterialPageRoute(
          builder: (_) => EchoSpaceDecorationPage(
            characterId: character.id,
            initialConfig: _spaceDecoration,
          ),
        ),
      );
      if (updated != null && mounted) {
        setState(() => _spaceDecoration = updated);
      }
      return;
    }
    _showMessage('敬请期待');
  }

  Future<void> _openGiftCollection() async {
    final character = _spaceCharacter;
    if (character == null) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RelationshipGiftPage(
          characterId: character.id,
          characterName: _displayName,
        ),
      ),
    );
    if (changed == true) await _loadPage();
  }

  Future<void> _openRelationshipGrowth() async {
    final character = _spaceCharacter;
    final profile = _growthProfile;
    if (character == null || profile == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => RelationshipGrowthPage(
          character: character,
          initialProfile: profile,
          chatInteractionCount: _chatInteractionCount,
          echoInteractionCount: _items
              .where((item) => item.isLiked || item.isCollected)
              .length,
          sharedExperienceCount: _memories.length,
        ),
      ),
    );
    await _loadPage();
  }

  Future<void> _openVisitorList() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => EchoVisitorListPage(visitors: _visitors),
      ),
    );
  }


  Future<void> _editSignature() async {
    final controller = TextEditingController(text: _echoProfile.signature);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('编辑空间签名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: '这里记录我的生活。',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    final updated = _echoProfile.copyWith(signature: value.trim());
    try {
      await EchoProfileStorageService(ownerId: _ownerId).saveProfile(updated);
      if (mounted) setState(() => _echoProfile = updated);
    } catch (_) {
      _showMessage('签名暂时没有保存成功。');
    }
  }

  Future<void> _openAuthorSpace(EchoItem item) async {
    if (!_isPublicTimeline) return;
    if (item.characterId == _userEchoId) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => const PeiLinkEchoPage()),
      );
      return;
    }
    final character = _characterForItem(item);
    if (character == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => PeiLinkEchoPage(character: character)),
    );
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
      debugPrint('保存 Echo 失败：$error');
      _showMessage('保存失败，请稍后再试');
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
          interactionStats: _interactionStats[item.id],
          userProfile: _userProfile,
          character: _characterForItem(item),
          characters: _characters,
          currentSpaceCharacterId: _isCharacterSpace ? _ownerId : '',
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

  Future<void> _openCommentAuthorSpace(EchoComment comment) async {
    final character = EchoCommentAuthorService.characterFor(
      comment,
      _characters,
    );
    if (character == null) return;
    if (_isCharacterSpace && character.id == _ownerId) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => PeiLinkEchoPage(character: character)),
    );
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
    final path = character?.effectiveSocialAvatarPath.trim() ?? '';
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
        : (_character?.effectiveSocialAvatarPath.trim() ?? '');
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
        _isUserPage ? Icons.person_rounded : Icons.auto_awesome_rounded,
        size: size * 0.45,
        color: const Color(0xFF6F7D86),
      ),
    );
  }

  Widget _cover() {
    return _SpaceBackground(config: _spaceDecoration);
  }

  @override
  Widget build(BuildContext context) {
    return ThemeBackgroundContainer(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: _loading
              ? const _EchoSpaceLoadingState()
              : _isCharacterSpace
              ? _buildCharacterSpace()
              : _isUserPage && !_isPublicTimeline
              ? _buildUserSpace()
              : _buildClassicEcho(),
        ),
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
            child: _isPublicTimeline
                ? _PublicEchoHeader(
                    onBack: widget.embedded
                        ? null
                        : () => Navigator.maybePop(context),
                    avatar: _avatar(size: 32),
                    onOpenMyEcho: widget.embedded ? null : _openMyEchoSpace,
                    onCreate: widget.embedded ? null : _showCreateMenu,
                  )
                : _EchoLifeHeader(
                    cover: _cover(),
                    avatar: _avatar(),
                    displayName: _displayName,
                    signature: _signature,
                    onBack: widget.embedded
                        ? null
                        : () => Navigator.maybePop(context),
                    onCreate: _showCreateMenu,
                    onEditSignature: _editSignature,
                  ),
          ),
          if (_items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _isPublicTimeline
                  ? _QuietEmptyState(
                      onCreate: _showCreateMenu,
                      title: '还没有 Echo。',
                      subtitle: '记录第一段生活片段吧。',
                    )
                  : _QuietEmptyState(onCreate: _showCreateMenu),
            )
          else
            _timelineSliver(),
          const SliverToBoxAdapter(child: SizedBox(height: 42)),
        ],
      ),
    );
  }

  Widget _buildCharacterSpace() {
    final cardOpacity = switch (_spaceDecoration.themeMode) {
      EchoSpaceThemeMode.airy => 0.72,
      EchoSpaceThemeMode.balanced => 0.68,
      EchoSpaceThemeMode.immersive => 0.64,
    };
    final settingsRelation = _characterSettings?.relation.trim() ?? '';
    final characterRelation = _spaceCharacter?.relationship.trim() ?? '';
    final relationship = settingsRelation.isNotEmpty
        ? settingsRelation
        : characterRelation;
    final surfaceColor = Colors.white.withValues(alpha: cardOpacity);
    final summary = EchoSpaceSummary.fromExistingData(
      echoes: _items,
      interactionCount: _chatInteractionCount,
      sharedExperienceCount: _memories.length,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        _SpaceBackground(config: _spaceDecoration),
        Theme(
          data: Theme.of(context).copyWith(cardColor: surfaceColor),
          child: RefreshIndicator(
            onRefresh: _loadPage,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _CharacterSpaceHeader(
                    cover: _cover(),
                    avatar: _avatar(size: 92),
                    displayName: _displayName,
                    signature: _signature,
                    currentStatus: summary.currentStatus,
                    recentActivity: summary.recentActivity,
                    interactionCount: summary.interactionCount,
                    relationship: relationship,
                    metAt: _spaceCharacter?.createdAt,
                    sharedExperienceCount: _memories.length,
                    visitors: _visitors,
                    growthProfile: _growthProfile,
                    onBack: () => Navigator.maybePop(context),
                    onCreate: _showCreateMenu,
                    onMore: _showSpaceMoreMenu,
                    onEditSignature: _editSignature,
                    onOpenRelationship: () =>
                        setState(() => _spaceTabIndex = 3),
                    onOpenGift: _openGiftCollection,
                    onOpenGrowth: _openRelationshipGrowth,
                    onOpenVisitors: _openVisitorList,
                    onOpenInteractions: () =>
                        setState(() => _spaceTabIndex = 2),
                    onOpenPlaceholder: () => _showMessage('敬请期待'),
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _CharacterSpaceTabHeader(
                    currentIndex: _spaceTabIndex,
                    onChanged: (index) =>
                        setState(() => _spaceTabIndex = index),
                    surfaceColor: surfaceColor,
                    isUserSpace: false,
                  ),
                ),
                ..._characterSpaceContentSlivers(),
                const SliverToBoxAdapter(child: SizedBox(height: 42)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUserSpace() {
    const surfaceColor = Color(0xE8FFFFFF);
    return Stack(
      fit: StackFit.expand,
      children: [
        const _SpaceBackground(config: EchoSpaceDecorationConfig()),
        Theme(
          data: Theme.of(context).copyWith(cardColor: surfaceColor),
          child: RefreshIndicator(
            onRefresh: _loadPage,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _UserSpaceHeader(
                    cover: _cover(),
                    avatar: _avatar(size: 92),
                    displayName: _displayName,
                    signature: _signature,
                    onBack: () => Navigator.maybePop(context),
                    onCreate: _showCreateMenu,
                    onEditSignature: _editSignature,
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _CharacterSpaceTabHeader(
                    currentIndex: _spaceTabIndex,
                    onChanged: (index) =>
                        setState(() => _spaceTabIndex = index),
                    surfaceColor: surfaceColor,
                    isUserSpace: true,
                  ),
                ),
                ..._userSpaceContentSlivers(),
                const SliverToBoxAdapter(child: SizedBox(height: 42)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _userSpaceContentSlivers() {
    return switch (_spaceTabIndex) {
      1 => _albumSlivers(),
      4 => _visitorSlivers(),
      _ => [
        if (_items.isEmpty)
          SliverToBoxAdapter(
            child: SizedBox(
              height: 300,
              child: _QuietEmptyState(
                onCreate: _showCreateMenu,
                spaceStyle: true,
                title: '还没有留下 Echo。',
                subtitle: '记录第一段属于你的生活。',
              ),
            ),
          )
        else
          _timelineSliver(spaceStyle: true),
      ],
    };
  }

  List<Widget> _characterSpaceContentSlivers() {
    return switch (_spaceTabIndex) {
      0 => [
        if (_items.isEmpty)
          SliverToBoxAdapter(
            child: SizedBox(
              height: 300,
              child: _QuietEmptyState(
                onCreate: _showCreateMenu,
                spaceStyle: true,
              ),
            ),
          )
        else
          _timelineSliver(spaceStyle: true),
      ],
      1 => _albumSlivers(),
      2 => _memorySlivers(),
      3 => _relationshipSlivers(),
      _ => _visitorSlivers(),
    };
  }

  List<Widget> _visitorSlivers() {
    if (_visitors.isEmpty) {
      return const [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(14, 14, 14, 8),
          sliver: SliverToBoxAdapter(child: _VisitorEmptyCard()),
        ),
      ];
    }
    return [
      const SliverPadding(
        padding: EdgeInsets.fromLTRB(18, 16, 18, 2),
        sliver: SliverToBoxAdapter(
          child: Text(
            '最近来访',
            style: TextStyle(
              color: Color(0xFF43535C),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        sliver: SliverList.separated(
          itemCount: _visitors.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) =>
              EchoVisitorCard(record: _visitors[index]),
        ),
      ),
    ];
  }

  List<String> get _albumImagePaths {
    return EchoAlbumService.imagePathsFor(_items);
  }

  List<Widget> _albumSlivers() {
    final paths = _albumImagePaths;
    if (paths.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: SizedBox(
            height: 300,
            child: _SpaceEmptyState(
              icon: Icons.photo_library_outlined,
              message: '这里还没有留下照片。',
            ),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
        sliver: SliverGrid.builder(
          itemCount: paths.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 7,
            crossAxisSpacing: 7,
          ),
          itemBuilder: (context, index) {
            final path = paths[index];
            return _AlbumTile(
              path: path,
              onTap: File(path).existsSync()
                  ? () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _AlbumImagePreview(path: path),
                      ),
                    )
                  : null,
            );
          },
        ),
      ),
    ];
  }

  List<Widget> _memorySlivers() {
    if (_memoriesLoadFailed) {
      return [
        SliverToBoxAdapter(
          child: SizedBox(
            height: 300,
            child: _SpaceEmptyState(
              icon: Icons.cloud_off_outlined,
              message: '回忆暂时没有加载成功。',
              actionLabel: '重新加载',
              onAction: _loadPage,
            ),
          ),
        ),
      ];
    }
    if (_memories.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: SizedBox(
            height: 300,
            child: _SpaceEmptyState(
              icon: Icons.auto_stories_outlined,
              message: '未来的重要瞬间，会记录在这里。',
            ),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
        sliver: SliverList.separated(
          itemCount: _memories.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) =>
              _MemoryCard(memory: _memories[index]),
        ),
      ),
    ];
  }

  List<Widget> _relationshipSlivers() {
    final character = _spaceCharacter;
    final settingsRelation = _characterSettings?.relation.trim() ?? '';
    final characterRelation = character?.relationship.trim() ?? '';
    final relationship = settingsRelation.isNotEmpty
        ? settingsRelation
        : characterRelation;
    final metAt = character?.createdAt;
    final hasKnownMeetingTime =
        metAt != null && metAt.year > 1970 && !metAt.isAfter(DateTime.now());
    final knownMeetingTime = hasKnownMeetingTime ? metAt : null;
    final daysKnown = knownMeetingTime == null
        ? null
        : _daysSince(knownMeetingTime, DateTime.now());
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
        sliver: SliverList.list(
          children: [
            RelationshipArchiveCard(
              relationship: relationship.isEmpty ? '关系尚未定义' : relationship,
              metAt: knownMeetingTime,
              daysKnown: daysKnown,
              sharedExperienceCount: _memories.length,
            ),
            const SizedBox(height: 11),
            EchoInteractionSummaryEntry(
              interactionCount: _chatInteractionCount,
              sharedExperienceCount: _memories.length,
              onTap: () => setState(() => _spaceTabIndex = 2),
            ),
            const SizedBox(height: 11),
            _BondQuickCards(
              growthProfile: _growthProfile,
              onOpenGift: _openGiftCollection,
              onOpenGrowth: _openRelationshipGrowth,
            ),
            const SizedBox(height: 11),
            const RelationshipTimelineCard(),
            const SizedBox(height: 11),
            RelationshipGiftEntryCard(onTap: _openGiftCollection),
          ],
        ),
      ),
    ];
  }

  SliverList _timelineSliver({bool spaceStyle = false}) {
    return SliverList.builder(
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        return _TimelineItem(
          avatar: _avatarForItem(item),
          displayName: _displayNameForItem(item),
          item: item,
          stats: _interactionStats[item.id],
          onLike: () => _toggleLike(item),
          onCollect: () => _toggleCollected(item),
          onComment: () => _openComments(item),
          onCommentAuthorTap: _openCommentAuthorSpace,
          onDelete: () => _deleteItem(item),
          onAuthorTap:
              _isPublicTimeline &&
                  (item.characterId == _userEchoId ||
                      _characterForItem(item) != null)
              ? () => _openAuthorSpace(item)
              : null,
          onOpenMemory: item.isFromSharedExperience && _isCharacterSpace
              ? () => setState(() => _spaceTabIndex = 2)
              : null,
          showAiBadge: item.characterId != _userEchoId,
          spaceStyle: true,
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
    required this.currentStatus,
    required this.recentActivity,
    required this.interactionCount,
    required this.relationship,
    required this.metAt,
    required this.sharedExperienceCount,
    required this.visitors,
    required this.growthProfile,
    required this.onBack,
    required this.onCreate,
    required this.onMore,
    required this.onEditSignature,
    required this.onOpenRelationship,
    required this.onOpenGift,
    required this.onOpenGrowth,
    required this.onOpenVisitors,
    required this.onOpenInteractions,
    required this.onOpenPlaceholder,
  });

  final Widget cover;
  final Widget avatar;
  final String displayName;
  final String signature;
  final String currentStatus;
  final String recentActivity;
  final int interactionCount;
  final String relationship;
  final DateTime? metAt;
  final int sharedExperienceCount;
  final List<EchoVisitorRecord> visitors;
  final RelationshipGrowthProfile? growthProfile;
  final VoidCallback onBack;
  final VoidCallback onCreate;
  final VoidCallback onMore;
  final VoidCallback onEditSignature;
  final VoidCallback onOpenRelationship;
  final VoidCallback onOpenGift;
  final VoidCallback onOpenGrowth;
  final VoidCallback onOpenVisitors;
  final VoidCallback onOpenInteractions;
  final VoidCallback onOpenPlaceholder;

  // Retained for the legacy relationship card while existing layouts migrate.
  // ignore: unused_element
  String? get _relationshipLabel {
    const emptyValues = {'', '未设置', '暂未设置', '未填写'};
    return emptyValues.contains(relationship) ? null : relationship;
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.transparent,
      child: Column(
        children: [
          SizedBox(
            height: 218,
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                Material(
                  color: Colors.transparent,
                  child: cover,
                ),
                const IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x77000000),
                          Colors.transparent,
                          Color(0x33000000),
                        ],
                        stops: [0, 0.38, 1],
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
                  child: Row(
                    children: [
                      _SpaceRoundButton(
                        tooltip: '背景音乐',
                        icon: Icons.music_note_rounded,
                        onTap: onOpenPlaceholder,
                      ),
                      const SizedBox(width: 7),
                      _SpaceRoundButton(
                        tooltip: '更多',
                        icon: Icons.more_horiz_rounded,
                        onTap: onMore,
                      ),
                      const SizedBox(width: 7),
                      _SpaceRoundButton(
                        tooltip: '发布 Echo',
                        icon: Icons.add_rounded,
                        onTap: onCreate,
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 22,
                  bottom: -28,
                  child: Container(
                    width: 88,
                    height: 88,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFFB7D5F4,
                          ).withValues(alpha: 0.46),
                          blurRadius: 22,
                          spreadRadius: 3,
                        ),
                      ],
                    ),
                    child: ClipOval(child: avatar),
                  ),
                ),
                const Positioned(
                  left: 132,
                  bottom: 12,
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
            padding: const EdgeInsets.fromLTRB(132, 4, 20, 0),
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
                  const SizedBox(width: 7),
                  const AiVerifiedBadge(size: 16),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(132, 3, 20, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                onTap: onEditSignature,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
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
                      const SizedBox(width: 5),
                      const Icon(
                        Icons.edit_outlined,
                        size: 13,
                        color: Color(0xFFA0A8AF),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          EchoCharacterActivityStrip(
            currentStatus: currentStatus,
            recentActivity: recentActivity,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _UserSpaceHeader extends StatelessWidget {
  const _UserSpaceHeader({
    required this.cover,
    required this.avatar,
    required this.displayName,
    required this.signature,
    required this.onBack,
    required this.onCreate,
    required this.onEditSignature,
  });

  final Widget cover;
  final Widget avatar;
  final String displayName;
  final String signature;
  final VoidCallback onBack;
  final VoidCallback onCreate;
  final VoidCallback onEditSignature;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 218,
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              Material(
                color: Colors.transparent,
                child: cover,
              ),
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x77000000),
                        Colors.transparent,
                        Color(0x33000000),
                      ],
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
                bottom: -28,
                child: Container(
                  width: 88,
                  height: 88,
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Color(0x55B7D5F4), blurRadius: 22),
                    ],
                  ),
                  child: ClipOval(child: avatar),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(132, 6, 20, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '我的 Echo',
                  key: ValueKey('my-echo-title'),
                  style: TextStyle(
                    color: Color(0xFF6F8FA3),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF1B2028),
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(132, 3, 20, 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: onEditSignature,
              borderRadius: BorderRadius.circular(8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
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
                  const SizedBox(width: 5),
                  const Icon(
                    Icons.edit_outlined,
                    size: 13,
                    color: Color(0xFFA0A8AF),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
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

// Kept as a compatibility widget for older space layouts.
// ignore: unused_element
class _SpaceRelationshipCard extends StatelessWidget {
  const _SpaceRelationshipCard({
    required this.relationship,
    required this.metAt,
    required this.sharedExperienceCount,
    required this.interactionCount,
    required this.onOpen,
  });

  final String? relationship;
  final DateTime? metAt;
  final int sharedExperienceCount;
  final int interactionCount;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final meetingTime = _validPastDate(metAt);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.fromLTRB(15, 12, 15, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).cardColor,
            Colors.white.withValues(alpha: 0.42),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x73FFFFFF), width: 0.7),
        boxShadow: const [
          BoxShadow(
            color: Color(0x091E3442),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.favorite_rounded,
                size: 19,
                color: Color(0xFFE989A0),
              ),
              const SizedBox(width: 9),
              const Text(
                '羁绊',
                style: TextStyle(
                  color: Color(0xFF34434D),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    '与你的关系',
                    style: TextStyle(color: Color(0xFF9AA3A8), fontSize: 8.5),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    relationship ?? '尚未定义',
                    style: const TextStyle(
                      color: Color(0xFFC96F86),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              sharedExperienceCount == 0
                  ? '故事才刚刚开始。'
                  : '你们一起留下了 $sharedExperienceCount 段回忆。',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF69777F),
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _SpaceProfileMetric(
                  label: '相识时间',
                  value: meetingTime == null
                      ? '未知'
                      : _formatMemoryDate(meetingTime),
                ),
              ),
              const _SpaceMetricDivider(),
              Expanded(
                child: _SpaceProfileMetric(
                  label: '互动次数',
                  value: '$interactionCount 次',
                ),
              ),
              const _SpaceMetricDivider(),
              Expanded(
                child: _SpaceProfileMetric(
                  label: '共同经历',
                  value: '$sharedExperienceCount 件',
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onOpen,
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.chevron_right_rounded, size: 17),
              label: const Text('查看记录'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF718995),
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpaceMetricDivider extends StatelessWidget {
  const _SpaceMetricDivider();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 30,
      child: VerticalDivider(width: 1, color: Color(0xFFE1E7EA)),
    );
  }
}

class _SpaceProfileMetric extends StatelessWidget {
  const _SpaceProfileMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF7A858C),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF65737B),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _BondQuickCards extends StatelessWidget {
  const _BondQuickCards({
    required this.growthProfile,
    required this.onOpenGift,
    required this.onOpenGrowth,
  });

  final RelationshipGrowthProfile? growthProfile;
  final VoidCallback onOpenGift;
  final VoidCallback onOpenGrowth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        height: 110,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _RelationshipGrowthQuickCard(
                profile: growthProfile,
                onTap: onOpenGrowth,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _BondSmallCard(
                icon: Icons.card_giftcard_rounded,
                title: '收到礼物',
                value: '${growthProfile?.gifts.length ?? 0} 件',
                footer: '查看礼物  ›',
                onTap: onOpenGift,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RelationshipGrowthQuickCard extends StatelessWidget {
  const _RelationshipGrowthQuickCard({
    required this.profile,
    required this.onTap,
  });

  final RelationshipGrowthProfile? profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final level = profile?.levelFor() ?? 1;
    final stage =
        profile?.stageFor() ?? RelationshipGrowthConfig.standard.stageFor(1);
    final required =
        profile?.nextLevelExperienceFor() ??
        RelationshipGrowthConfig.standard.experienceForNextLevel(1);
    final current = profile?.currentExperienceFor() ?? 0;
    final progress = required == 0 ? 1.0 : current / required;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          height: 110,
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
          decoration: _bondSmallCardDecoration(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _BondSmallTitle(
                icon: Icons.favorite_rounded,
                title: '关系成长',
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  Text(
                    'Lv.$level',
                    style: const TextStyle(
                      color: Color(0xFFD8758C),
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    stage,
                    style: const TextStyle(
                      color: Color(0xFF737F86),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(4)),
                child: LinearProgressIndicator(
                  value: progress.clamp(0, 1),
                  minHeight: 5,
                  backgroundColor: const Color(0x55FFFFFF),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFFE992A7),
                  ),
                ),
              ),
              const Spacer(),
              const Text(
                '查看成长  ›',
                style: TextStyle(color: Color(0xFF8B9499), fontSize: 9),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BondSmallCard extends StatelessWidget {
  const _BondSmallCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.footer,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final String footer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          height: 110,
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
          decoration: _bondSmallCardDecoration(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BondSmallTitle(icon: icon, title: title),
              const SizedBox(height: 7),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF59676F),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                footer,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF929CA1), fontSize: 9.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BondSmallTitle extends StatelessWidget {
  const _BondSmallTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFFE4869C)),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF5C6870),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

BoxDecoration _bondSmallCardDecoration(BuildContext context) {
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Theme.of(context).cardColor,
        Colors.white.withValues(alpha: 0.34),
      ],
    ),
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: const Color(0x59FFFFFF), width: 0.6),
  );
}

class _CharacterSpaceTabHeader extends SliverPersistentHeaderDelegate {
  const _CharacterSpaceTabHeader({
    required this.currentIndex,
    required this.onChanged,
    required this.surfaceColor,
    required this.isUserSpace,
  });

  static const _labels = ['动态', '相册', '回忆', '关系', '访客'];
  static const _userTabs = [(0, '动态'), (1, '相册'), (4, '访客')];

  final int currentIndex;
  final ValueChanged<int> onChanged;
  final Color surfaceColor;
  final bool isUserSpace;

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
        color: Colors.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                surfaceColor.withValues(alpha: overlapsContent ? 0.72 : 0.18),
                surfaceColor.withValues(alpha: overlapsContent ? 0.90 : 0.78),
              ],
            ),
          ),
          child: Row(
            children:
                (isUserSpace
                        ? _userTabs
                        : List.generate(_labels.length, (i) => (i, _labels[i])))
                    .map((entry) {
                      final index = entry.$1;
                      final selected = currentIndex == index;
                      return Expanded(
                        child: InkWell(
                          onTap: () => onChanged(index),
                          splashColor: const Color(0x146E9AB2),
                          highlightColor: const Color(0x0A6E9AB2),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Text(
                                entry.$2,
                                style: TextStyle(
                                  color: selected
                                      ? const Color(0xFF496F84)
                                      : const Color(0xFF8E969D),
                                  fontSize: 13.5,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                              if (selected)
                                Positioned(
                                  bottom: 1,
                                  child: SizedBox(
                                    width: 30,
                                    height: 3,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFF79AFC8),
                                            Color(0xFF8B86C9),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.vertical(
                                          top: Radius.circular(3),
                                        ),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Color(0x3379AFC8),
                                            blurRadius: 5,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    })
                    .toList(),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _CharacterSpaceTabHeader oldDelegate) {
    return oldDelegate.currentIndex != currentIndex ||
        oldDelegate.surfaceColor != surfaceColor ||
        oldDelegate.isUserSpace != isUserSpace;
  }
}

class _SpaceBackground extends StatelessWidget {
  const _SpaceBackground({required this.config});

  final EchoSpaceDecorationConfig config;

  @override
  Widget build(BuildContext context) {
    final background = config.background.trim();
    final veilOpacity = switch (config.themeMode) {
      EchoSpaceThemeMode.airy => 0.32,
      EchoSpaceThemeMode.balanced => 0.18,
      EchoSpaceThemeMode.immersive => 0.08,
    };
    return Stack(
      fit: StackFit.expand,
      children: [
        if (background.isEmpty)
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF3F5F4), Color(0xFFE6EEF0)],
              ),
            ),
          )
        else
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 1.1, sigmaY: 1.1),
            child: Image.asset(
              background,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const ColoredBox(color: Color(0xFFF1F3F3)),
            ),
          ),
        ColoredBox(color: Colors.white.withValues(alpha: veilOpacity)),
      ],
    );
  }
}

class _AlbumTile extends StatelessWidget {
  const _AlbumTile({required this.path, required this.onTap});

  final String path;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF0F3F4),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Image.file(
          File(path),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const Center(
            child: Icon(Icons.broken_image_outlined, color: Color(0xFFA4AFB5)),
          ),
        ),
      ),
    );
  }
}

class _AlbumImagePreview extends StatelessWidget {
  const _AlbumImagePreview({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('照片'),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4,
          child: Image.file(
            File(path),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text('照片暂时无法查看。', style: TextStyle(color: Colors.white70)),
            ),
          ),
        ),
      ),
    );
  }
}

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({required this.memory});

  final SharedExperience memory;

  IconData get _icon => switch (memory.type) {
    SharedExperienceType.encounter => Icons.waving_hand_outlined,
    SharedExperienceType.conversation => Icons.forum_outlined,
    SharedExperienceType.cooperation => Icons.handshake_outlined,
    SharedExperienceType.help => Icons.volunteer_activism_outlined,
    SharedExperienceType.celebration => Icons.celebration_outlined,
    SharedExperienceType.travel => Icons.route_outlined,
    SharedExperienceType.dailyLife => Icons.local_cafe_outlined,
    SharedExperienceType.tension => Icons.cloud_outlined,
    SharedExperienceType.other => Icons.auto_stories_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final description = memory.detail.trim().isEmpty
        ? memory.summary.trim()
        : memory.detail.trim();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x70FFFFFF), width: 0.7),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08203744),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                color: Color(0xFFEAF2F7),
                shape: BoxShape.circle,
              ),
              child: Icon(_icon, size: 21, color: const Color(0xFF66899C)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    memory.type.label,
                    style: const TextStyle(
                      color: Color(0xFF2F3940),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _formatMemoryDate(memory.occurredAt),
                    style: const TextStyle(
                      color: Color(0xFF9AA2A8),
                      fontSize: 11,
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 9),
                    Text(
                      description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF6C747A),
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RelationshipOverviewCardLegacy extends StatelessWidget {
  const RelationshipOverviewCardLegacy({
    super.key,
    required this.relationship,
    required this.metAt,
    required this.daysKnown,
    required this.sharedExperienceCount,
  });

  final String relationship;
  final DateTime? metAt;
  final int? daysKnown;
  final int sharedExperienceCount;

  @override
  Widget build(BuildContext context) {
    final meetingTime = metAt;
    return _SpaceSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SpaceSectionTitle(
            icon: Icons.folder_shared_outlined,
            title: '羁绊档案',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _BondArchiveField(
                label: '关系类型',
                value: relationship,
                emphasized: true,
              ),
              _BondArchiveField(
                label: '相识时间',
                value: meetingTime == null
                    ? '未知'
                    : _formatMemoryDate(meetingTime),
              ),
              _BondArchiveField(
                label: '陪伴天数',
                value: daysKnown == null ? '未知' : '$daysKnown 天',
              ),
              _BondArchiveField(
                label: '共同经历',
                value: sharedExperienceCount == 0
                    ? '暂无'
                    : '$sharedExperienceCount 件',
              ),
            ],
          ),
          const SizedBox(height: 17),
          const Text(
            '关于你们',
            style: TextStyle(
              color: Color(0xFF596870),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            '未来会记录属于你们的故事。',
            style: TextStyle(
              color: Color(0xFF7F8A90),
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
          if (daysKnown case final days?) ...[
            const SizedBox(height: 12),
            Text(
              '已经相识 $days 天',
              style: const TextStyle(
                color: Color(0xFFB87586),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BondArchiveField extends StatelessWidget {
  const _BondArchiveField({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 70,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF98A2A8), fontSize: 10.5),
          ),
          const SizedBox(height: 5),
          Container(
            padding: emphasized
                ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
                : EdgeInsets.zero,
            decoration: emphasized
                ? BoxDecoration(
                    color: const Color(0x66FFF0F4),
                    borderRadius: BorderRadius.circular(10),
                  )
                : null,
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: emphasized
                    ? const Color(0xFFC96F86)
                    : const Color(0xFF53636B),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RelationshipFeatureCardLegacy extends StatelessWidget {
  const RelationshipFeatureCardLegacy({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return _SpaceSectionCard(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: Color(0xFFF1F4F6),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 21, color: const Color(0xFF8197A2)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF3C474D),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    color: Color(0xFF969FA4),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFFBCC4C8)),
        ],
      ),
    );
  }
}

class _SpaceSectionCard extends StatelessWidget {
  const _SpaceSectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x70FFFFFF), width: 0.7),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08203744),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class _SpaceSectionTitle extends StatelessWidget {
  const _SpaceSectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 19, color: const Color(0xFF7594A5)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF3B474E),
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _SpaceEmptyState extends StatelessWidget {
  const _SpaceEmptyState({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 54),
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
              child: Icon(icon, color: const Color(0xFF91A8B5), size: 27),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF7D868C), fontSize: 13),
            ),
            if (actionLabel case final label?) ...[
              const SizedBox(height: 10),
              TextButton(onPressed: onAction, child: Text(label)),
            ],
          ],
        ),
      ),
    );
  }
}

class _EchoSpaceLoadingState extends StatelessWidget {
  const _EchoSpaceLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.graphic_eq_rounded, size: 28, color: Color(0xFF91A8B5)),
          SizedBox(height: 10),
          Text(
            '正在打开这片生活空间…',
            style: TextStyle(color: Color(0xFF7D868C), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _VisitorEmptyCard extends StatelessWidget {
  const _VisitorEmptyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x70FFFFFF), width: 0.7),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08203744),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(18, 17, 18, 15),
            child: _SpaceSectionTitle(
              icon: Icons.directions_walk_rounded,
              title: '最近来访',
            ),
          ),
          Divider(height: 1, color: Color(0xFFE7ECEF)),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 42, 20, 46),
            child: Column(
              children: [
                Icon(
                  Icons.directions_walk_outlined,
                  size: 42,
                  color: Color(0xFF9BB0BB),
                ),
                SizedBox(height: 16),
                Text(
                  '这里会留下来到这个空间的人。',
                  style: TextStyle(
                    color: Color(0xFF4D5A62),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '这里还没有留下痕迹',
                  style: TextStyle(color: Color(0xFF8B969C), fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatMemoryDate(DateTime time) {
  final month = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  return '${time.year}.$month.$day';
}

DateTime? _validPastDate(DateTime? value) {
  if (value == null || value.year <= 1970 || value.isAfter(DateTime.now())) {
    return null;
  }
  return value;
}

int _daysSince(DateTime start, DateTime now) {
  final startDate = DateTime(start.year, start.month, start.day);
  final today = DateTime(now.year, now.month, now.day);
  return today.difference(startDate).inDays + 1;
}

class _PublicEchoHeader extends StatelessWidget {
  const _PublicEchoHeader({
    this.onBack,
    this.avatar,
    this.onOpenMyEcho,
    this.onCreate,
  });

  final VoidCallback? onBack;
  final Widget? avatar;
  final VoidCallback? onOpenMyEcho;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(onBack == null ? 10 : 2, 8, 8, 12),
        child: Row(
          children: [
            if (onBack != null)
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              )
            else
              const SizedBox(width: 8),
            if (onOpenMyEcho != null) ...[
              const SizedBox(width: 2),
              InkWell(
                key: const ValueKey('echo-public-my-echo'),
                borderRadius: BorderRadius.circular(19),
                onTap: onOpenMyEcho,
                child: Container(
                  width: 38,
                  height: 38,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3E7E9),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFD3DDE2)),
                  ),
                  child: ClipOval(child: avatar ?? const SizedBox.shrink()),
                ),
              ),
            ],
            const SizedBox(width: 8),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Echo',
                    style: TextStyle(
                      color: Color(0xFF293943),
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    '看看大家最近留下的生活片段',
                    style: TextStyle(color: Color(0xFF8B969D), fontSize: 12),
                  ),
                ],
              ),
            ),
            if (onCreate != null)
              IconButton(
                key: const ValueKey('echo-public-compose'),
                onPressed: onCreate,
                tooltip: '发布 Echo',
                icon: const Icon(
                  Icons.add_circle_outline_rounded,
                  color: Color(0xFF171717),
                  size: 25,
                ),
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
    required this.onEditSignature,
  });

  final Widget cover;
  final Widget avatar;
  final String displayName;
  final String signature;
  final VoidCallback? onBack;
  final VoidCallback onCreate;
  final VoidCallback onEditSignature;

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
                child: cover,
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
              if (onBack != null)
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
            child: InkWell(
              onTap: onEditSignature,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
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
                    const SizedBox(width: 5),
                    const Icon(
                      Icons.edit_outlined,
                      size: 14,
                      color: Color(0xFF98A2AA),
                    ),
                  ],
                ),
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
  const _QuietEmptyState({
    required this.onCreate,
    this.spaceStyle = false,
    this.title,
    this.subtitle,
  });

  final VoidCallback onCreate;
  final bool spaceStyle;
  final String? title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final resolvedTitle = title ?? '他的生活还没有开始记录';
    final resolvedSubtitle =
        subtitle ?? (spaceStyle ? '等待这个世界留下第一段故事' : '等待第一次 Echo');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onCreate,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 34),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F6F8),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFE2EBEF)),
                  ),
                  child: const Icon(
                    Icons.graphic_eq_rounded,
                    color: Color(0xFF8DA8B7),
                    size: 25,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  resolvedTitle,
                  style: const TextStyle(
                    color: Color(0xFF68757D),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  resolvedSubtitle,
                  style: const TextStyle(
                    color: Color(0xFFA8B0B5),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpandableEchoText extends StatefulWidget {
  const _ExpandableEchoText({required this.text});

  final String text;

  @override
  State<_ExpandableEchoText> createState() => _ExpandableEchoTextState();
}

class _ExpandableEchoTextState extends State<_ExpandableEchoText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final canExpand =
        widget.text.runes.length > 88 || widget.text.split('\n').length > 4;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.text,
          maxLines: _expanded ? null : 4,
          overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF27343C),
            fontSize: 14,
            height: 1.48,
          ),
        ),
        if (canExpand)
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.only(top: 4, right: 8, bottom: 2),
              child: Text(
                _expanded ? '收起' : '展开全文',
                style: const TextStyle(
                  color: Color(0xFF6F8FC0),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.avatar,
    required this.displayName,
    required this.item,
    required this.stats,
    required this.onLike,
    required this.onCollect,
    required this.onComment,
    required this.onDelete,
    required this.onCommentAuthorTap,
    this.onAuthorTap,
    this.onOpenMemory,
    this.showAiBadge = true,
    this.spaceStyle = false,
  });

  final Widget avatar;
  final String displayName;
  final EchoItem item;
  final EchoInteractionStats? stats;
  final VoidCallback onLike;
  final VoidCallback onCollect;
  final VoidCallback onComment;
  final VoidCallback onDelete;
  final ValueChanged<EchoComment> onCommentAuthorTap;
  final VoidCallback? onAuthorTap;
  final VoidCallback? onOpenMemory;

  /// The verified badge marks AI characters with an independent persona; the
  /// user's own Echo must never show it.
  final bool showAiBadge;
  final bool spaceStyle;

  Widget _buildSpaceCard(BuildContext context) {
    final visibleCommentCount = EchoCommentPreviewService.visibleComments(
      item.comments,
    ).length;
    final hasInteractions = item.likeCount > 0 || visibleCommentCount > 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x70FFFFFF), width: 0.7),
        boxShadow: const [
          BoxShadow(
            color: Color(0x091A3442),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFDCE8ED)),
                      ),
                      child: ClipOval(
                        child: GestureDetector(
                          onTap: onAuthorTap,
                          child: avatar,
                        ),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: InkWell(
                                  onTap: onAuthorTap,
                                  borderRadius: BorderRadius.circular(5),
                                  child: Text(
                                    displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF344E5D),
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              if (showAiBadge) ...[
                                const SizedBox(width: 6),
                                const AiVerifiedBadge(size: 14),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              const Flexible(
                                child: Text(
                                  '今天留下了一段 Echo',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Color(0xFF9AA5AB),
                                    fontSize: 10.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 7),
                              Container(
                                width: 3,
                                height: 3,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFBCC4C8),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 7),
                              Text(
                                _formatTime(item.createdAt),
                                style: const TextStyle(
                                  color: Color(0xFFAAB2B7),
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ),
                          if (stats case final interactionStats?) ...[
                            const SizedBox(height: 5),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.48),
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Text(
                                  interactionStats.heatLevel.label,
                                  style: const TextStyle(
                                    color: Color(0xFF7E8A91),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: '更多',
                      icon: const Icon(
                        Icons.more_horiz_rounded,
                        color: Color(0xFF9AA7AE),
                        size: 21,
                      ),
                      onSelected: (value) {
                        if (value == 'delete') onDelete();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'delete', child: Text('删除')),
                      ],
                    ),
                  ],
                ),
                if (item.sourceType != EchoSourceType.manual ||
                    item.sourceEvent.trim().isNotEmpty ||
                    item.characterState.trim().isNotEmpty) ...[
                  const SizedBox(height: 9),
                  _EchoLifeMeta(
                    item: item,
                    spaceStyle: true,
                    onTap: onOpenMemory,
                  ),
                ],
                if (item.content.trim().isNotEmpty) ...[
                  const SizedBox(height: 11),
                  _ExpandableEchoText(text: item.content),
                ],
                if (item.imagePaths.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _EchoImageGrid(paths: item.imagePaths),
                ],
                const SizedBox(height: 9),
                const Divider(height: 1, color: Color(0x66FFFFFF)),
                EchoInteractionBar(
                  likeCount: (stats?.likeCount ?? 0) + item.likeCount,
                  commentCount: visibleCommentCount > (stats?.commentCount ?? 0)
                      ? visibleCommentCount
                      : (stats?.commentCount ?? 0),
                  collectCount:
                      (stats?.collectCount ?? 0) + (item.isCollected ? 1 : 0),
                  viewCount: stats?.viewCount ?? 0,
                  isLiked: item.isLiked,
                  isCollected: item.isCollected,
                  onLike: onLike,
                  onComment: onComment,
                  onCollect: onCollect,
                ),
                if (hasInteractions) _buildSpaceInteractions(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpaceInteractions() {
    final visibleComments = EchoCommentPreviewService.visibleComments(
      item.comments,
    );
    final preview = EchoCommentPreviewService.select(visibleComments);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.likeCount > 0)
            Row(
              children: [
                const Icon(
                  Icons.favorite_rounded,
                  size: 14,
                  color: Color(0xFFE98EA3),
                ),
                const SizedBox(width: 5),
                Text(
                  '${item.likeCount} 个喜欢',
                  style: const TextStyle(
                    color: Color(0xFF607E8F),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          for (final comment in preview)
            Padding(
              padding: EdgeInsets.only(top: item.likeCount > 0 ? 6 : 2),
              child: InkWell(
                onTap: comment.commentType == EchoCommentType.aiCharacter
                    ? () => onCommentAuthorTap(comment)
                    : null,
                borderRadius: BorderRadius.circular(6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 9,
                      backgroundColor:
                          comment.commentType == EchoCommentType.aiCharacter
                          ? const Color(0xFFE4ECF8)
                          : const Color(0xFFECEFF1),
                      child: Icon(
                        comment.commentType == EchoCommentType.aiCharacter
                            ? Icons.auto_awesome_rounded
                            : Icons.person_outline_rounded,
                        size: 11,
                        color: const Color(0xFF718A9C),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text:
                                  comment.authorType ==
                                      EchoCommentAuthorType.user
                                  ? '我'
                                  : (comment.authorNameSnapshot.trim().isEmpty
                                        ? (comment.authorType ==
                                                  EchoCommentAuthorType
                                                      .character
                                              ? displayName
                                              : '世界居民')
                                        : comment.authorNameSnapshot.trim()),
                              style: const TextStyle(
                                color: Color(0xFF58768A),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (comment.replyToAuthorNameSnapshot
                                .trim()
                                .isNotEmpty) ...[
                              const TextSpan(text: ' 回复 '),
                              TextSpan(
                                text: comment.replyToAuthorNameSnapshot.trim(),
                                style: const TextStyle(
                                  color: Color(0xFF58768A),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                            const TextSpan(text: '：'),
                            TextSpan(text: comment.content),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF445159),
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (visibleComments.length > preview.length)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: InkWell(
                onTap: onComment,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '查看全部 ${visibleComments.length} 条评论',
                    style: const TextStyle(
                      color: Color(0xFF718A9C),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (spaceStyle) return _buildSpaceCard(context);
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
                if (item.sourceType != EchoSourceType.manual ||
                    item.sourceEvent.trim().isNotEmpty ||
                    item.characterState.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _EchoLifeMeta(item: item, onTap: onOpenMemory),
                ],
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
                                            EchoCommentAuthorType.user
                                        ? '我'
                                        : (comment.authorNameSnapshot
                                                  .trim()
                                                  .isEmpty
                                              ? (comment.authorType ==
                                                        EchoCommentAuthorType
                                                            .character
                                                    ? displayName
                                                    : '世界居民')
                                              : comment.authorNameSnapshot
                                                    .trim()),
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

class SpaceEchoActionLegacy extends StatelessWidget {
  const SpaceEchoActionLegacy({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF769CB1) : const Color(0xFF849198);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EchoLifeMeta extends StatelessWidget {
  const _EchoLifeMeta({
    required this.item,
    this.spaceStyle = false,
    this.onTap,
  });

  final EchoItem item;
  final bool spaceStyle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = spaceStyle
        ? const Color(0xFF6E7F9C)
        : const Color(0xFF697BA0);
    final background = spaceStyle
        ? Colors.white.withValues(alpha: 0.42)
        : const Color(0xFFF1F3FA);
    final content = Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            item.lifeType == EchoLifeType.memory && onTap != null
                ? '记忆 · 查看回忆 ›'
                : item.lifeType.label,
            style: TextStyle(
              color: foreground,
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (item.characterState.trim().isNotEmpty)
          Text(
            '· ${item.characterState.trim()}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: spaceStyle
                  ? const Color(0xFF9AA5AB)
                  : const Color(0xFF9A9FAE),
              fontSize: 9.5,
            ),
          ),
      ],
    );
    if (onTap == null) return content;
    return GestureDetector(onTap: onTap, child: content);
  }
}

class _EchoImageGrid extends StatelessWidget {
  const _EchoImageGrid({required this.paths});

  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    final cleanPaths = paths.where((path) => path.trim().isNotEmpty).toList();
    if (cleanPaths.isEmpty) return const SizedBox.shrink();
    if (cleanPaths.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: _EchoImageTile(path: cleanPaths.first),
        ),
      );
    }

    final columns = cleanPaths.length <= 4 ? 2 : 3;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cleanPaths.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 5,
        crossAxisSpacing: 5,
      ),
      itemBuilder: (context, index) => ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: _EchoImageTile(path: cleanPaths[index]),
      ),
    );
  }
}

class _EchoImageTile extends StatelessWidget {
  const _EchoImageTile({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    if (!file.existsSync()) {
      return const ColoredBox(
        color: Color(0xFFF0F2F5),
        child: Center(
          child: Icon(Icons.broken_image_outlined, color: Color(0xFFAAB3BA)),
        ),
      );
    }
    return Image.file(
      file,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const ColoredBox(
        color: Color(0xFFF0F2F5),
        child: Center(
          child: Icon(Icons.broken_image_outlined, color: Color(0xFFAAB3BA)),
        ),
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
