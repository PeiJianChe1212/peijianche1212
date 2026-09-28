import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/ai_character.dart';
import '../../models/group_chat.dart';
import '../../models/group_message.dart';
import '../../models/group_user_profile.dart';
import '../../services/character_registry_service.dart';
import '../../services/group_chat_storage_service.dart';
import '../../services/group_conversation_coordinator.dart';
import '../../services/group_memory_service.dart';
import '../../services/group_user_profile_storage_service.dart';
import '../../services/group_message_storage_service.dart';
import '../../services/api_settings_storage_service.dart';
import '../../services/third_party_consent_service.dart';
import '../../services/peilink_appearance_service.dart';
import '../../theme/app_theme_background.dart';
import '../../theme/chat_visual_theme.dart';
import '../../theme/effective_bubble_theme.dart';
import '../../widgets/chat/chat_bubble_surface.dart';
import '../../widgets/chat/chat_more_panel.dart';
import '../../widgets/group/group_visuals.dart';
import '../../widgets/group/group_avatar.dart';
import '../../widgets/theme/peilink_theme_scope.dart';
import '../../widgets/theme/peilink_themed_avatar.dart';
import '../chat_page.dart';
import 'group_chat_settings_page.dart';
import 'group_user_profile_page.dart';

class GroupChatPage extends StatefulWidget {
  const GroupChatPage({super.key, required this.groupId});

  final String groupId;

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage>
    with WidgetsBindingObserver {
  final GroupChatStorageService _groupStorage = GroupChatStorageService();
  final GroupConversationCoordinator _coordinator =
      GroupConversationCoordinator();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  late final GroupMessageStorageService _messageStorage =
      GroupMessageStorageService(groupId: widget.groupId);
  GroupChat? _group;
  List<GroupMessage> _messages = const [];
  Map<String, AiCharacter> _characters = const {};
  bool _loading = true;
  bool _replying = false;
  String? _typingCharacterId;
  GroupMessage? _replyingTo;
  int _replyGeneration = 0;
  int _lastMentionPopupLength = -1;
  bool _showMorePanel = false;
  String _userAvatarPath = '';
  bool _wasNearBottom = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    CharacterRegistryService.changes.addListener(_load);
    _scrollController.addListener(_rememberScrollPosition);
    _load();
  }

  void _rememberScrollPosition() {
    if (!_scrollController.hasClients) return;
    _wasNearBottom =
        _scrollController.position.maxScrollExtent -
            _scrollController.position.pixels <=
        80;
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (_wasNearBottom) {
      _scrollToBottom(delay: const Duration(milliseconds: 80));
    }
  }

  @override
  void dispose() {
    _replyGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    CharacterRegistryService.changes.removeListener(_load);
    _scrollController.removeListener(_rememberScrollPosition);
    _controller.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _groupStorage.loadGroup(widget.groupId),
      _messageStorage.loadMessages(),
      CharacterRegistryService().loadCharacters(),
      GroupUserProfileStorageService(groupId: widget.groupId).loadResolved(),
    ]);
    if (!mounted) return;
    final characters = results[2] as List<AiCharacter>;
    setState(() {
      _group = results[0] as GroupChat?;
      _messages = results[1] as List<GroupMessage>;
      _characters = {
        for (final character in characters) character.id: character,
      };
      _userAvatarPath = (results[3] as GroupUserProfile).avatarPath;
      _loading = false;
    });
    _scrollToBottom();
  }

  Future<void> _send() async {
    final content = _controller.text.trim();
    final group = _group;
    if (content.isEmpty || group == null) return;
    _closeMorePanel();
    // Third-party consent
    final apiSettings = await ApiSettingsStorageService().loadSettings();
    if (!mounted) return;
    final agreed = await ThirdPartyConsentService.instance.requestConsentIfNeeded(
      context,
      apiSettings.provider,
      apiSettings.baseUrl,
      ConsentPurpose.chat,
    );
    if (!agreed) return;

    // 用户插话即废止旧回合。已经落地的消息保留，尚未开始的回复停止。
    final generation = ++_replyGeneration;
    final mentionedIds = _extractMentionedIds(content, group);
    final message = GroupMessage(
      groupId: group.id,
      senderType: GroupSenderType.user,
      senderId: 'user',
      content: content,
      replyToMessageId: _replyingTo?.id,
      mentionedMemberIds: mentionedIds,
      sourceType: GroupMessageSource.userInput,
      status: GroupMessageStatus.sending,
    );
    final updatedMessages = [..._messages, message];
    final updatedGroup = group.copyWith(
      lastMessage: content,
      lastMessageAt: message.createdAt,
      lastActiveAt: message.createdAt,
      unreadCount: 0,
    );
    setState(() {
      _messages = updatedMessages;
      _group = updatedGroup;
      _controller.clear();
      _replyingTo = null;
      _replying = true;
      _typingCharacterId = null;
    });
    try {
      await Future.wait([
        _messageStorage.saveMessages(updatedMessages),
        _groupStorage.upsertGroup(updatedGroup),
      ]);
    } catch (_) {
      if (mounted) _markMessageStatus(message.id, GroupMessageStatus.failed);
      return;
    }
    if (!mounted) return;
    _markMessageStatus(message.id, GroupMessageStatus.sent);
    unawaited(_messageStorage.saveMessages(_messages));
    _scrollToBottom();
    // G3.4：活跃段结束后低频提取群聊共同经历；门槛与游标在服务内部兜底。
    GroupMemoryService.dispatchAfterMessagesSaved(
      groupId: group.id,
      groupName: group.name,
    );
    unawaited(_runReplies(generation));
  }

  void _markMessageStatus(String messageId, GroupMessageStatus status) {
    setState(() {
      _messages = [
        for (final item in _messages)
          item.id == messageId ? item.copyWith(status: status) : item,
      ];
    });
  }

  /// 失败重试：重新落库同一条消息，不重新生成整轮回复。
  Future<void> _retryMessage(GroupMessage message) async {
    _markMessageStatus(message.id, GroupMessageStatus.sending);
    try {
      await Future.wait([
        _messageStorage.saveMessages(_messages),
        if (_group != null) _groupStorage.upsertGroup(_group!),
      ]);
      if (!mounted) return;
      _markMessageStatus(message.id, GroupMessageStatus.sent);
    } catch (_) {
      if (!mounted) return;
      _markMessageStatus(message.id, GroupMessageStatus.failed);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('仍然发送失败，请稍后再试')));
    }
  }

  /// 群成员头像 → 复用既有单聊入口，不新建角色详情页。
  Future<void> _openMemberChat(String characterId) async {
    if (!_characters.containsKey(characterId)) return;
    await CharacterRegistryService().setActiveCharacter(characterId);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChatPage()),
    );
  }

  /// 群聊身份：按 groupId 独立，与全局 UserProfile 解耦。
  Future<void> _openGroupIdentity() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => GroupUserProfilePage(
          groupId: widget.groupId,
          groupName: _group?.name ?? '',
        ),
      ),
    );
  }

  /// 与单聊一致：+ 不弹 BottomSheet，直接在输入栏下方就地展开功能宫格。
  void _toggleMorePanel() {
    if (_loading) return;
    _inputFocusNode.unfocus();
    setState(() => _showMorePanel = !_showMorePanel);
    if (_showMorePanel) _scrollToBottom();
  }

  void _closeMorePanel() {
    if (!_showMorePanel || !mounted) return;
    setState(() => _showMorePanel = false);
  }

  Future<void> _runReplies(int generation) async {
    final group = _group;
    if (group == null) return;

    final plan = await _coordinator.createPlan(
      group: group,
      messages: List<GroupMessage>.from(_messages),
    );
    if (!_isCurrent(generation)) return;

    for (final step in plan.steps) {
      if (!_isCurrent(generation)) return;
      setState(() => _typingCharacterId = step.characterId);
      _scrollToBottom();

      final result = await _coordinator.generateStep(
        group: group,
        step: step,
        messages: List<GroupMessage>.from(_messages),
      );
      if (!_isCurrent(generation)) return;
      if (result == null || result.messages.isEmpty) continue;

      for (final content in result.messages) {
        if (!_isCurrent(generation)) return;
        final characterMessage = GroupMessage(
          groupId: group.id,
          senderType: GroupSenderType.character,
          senderId: result.characterId,
          content: content,
          mentionedMemberIds: _extractMentionedIds(content, group),
          sourceType: GroupMessageSource.characterReply,
        );
        final nextMessages = [..._messages, characterMessage];
        final latestGroup = (_group ?? group).copyWith(
          lastMessage: content,
          lastMessageAt: characterMessage.createdAt,
          lastActiveAt: characterMessage.createdAt,
          unreadCount: 0,
          members: (_group ?? group).members.map((member) {
            return member.characterId == result.characterId
                ? member.copyWith(lastSpokeAt: characterMessage.createdAt)
                : member;
          }).toList(),
        );
        if (!mounted) return;
        setState(() {
          _messages = nextMessages;
          _group = latestGroup;
        });
        await Future.wait([
          _messageStorage.saveMessages(nextMessages),
          _groupStorage.upsertGroup(latestGroup),
        ]);
        _scrollToBottom();
        if (result.messages.length > 1) {
          await Future<void>.delayed(const Duration(milliseconds: 360));
        }
      }
    }

    if (!_isCurrent(generation)) return;
    setState(() {
      _replying = false;
      _typingCharacterId = null;
    });
    GroupMemoryService.dispatchAfterMessagesSaved(
      groupId: group.id,
      groupName: group.name,
    );
  }

  List<String> _extractMentionedIds(String content, GroupChat group) {
    final result = <String>{};
    if (content.contains('@全体成员') || content.contains('@所有人')) {
      result.addAll(group.memberCharacterIds);
    }
    if (content.contains('@用户')) {
      result.add('user');
    }
    for (final id in group.memberCharacterIds) {
      final character = _characters[id];
      if (character == null) continue;
      final names = <String>{
        character.displayName.trim(),
        character.characterName.trim(),
        character.remark.trim(),
      }..removeWhere((name) => name.isEmpty);
      if (names.any((name) => content.contains('@$name'))) {
        result.add(id);
      }
    }
    return result.toList(growable: false);
  }

  Future<void> _showMentionPicker() async {
    final group = _group;
    if (group == null || !mounted) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final members = group.memberCharacterIds
            .map((id) => _characters[id])
            .whereType<AiCharacter>()
            .toList(growable: false);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('选择提醒的人'), dense: true),
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.groups_rounded)),
                title: const Text('全体成员'),
                onTap: () => Navigator.pop(context, '全体成员'),
              ),
              for (final character in members)
                ListTile(
                  leading: _CharacterAvatar(character: character),
                  title: Text(character.displayName),
                  onTap: () => Navigator.pop(context, character.displayName),
                ),
            ],
          ),
        );
      },
    );
    if (!mounted || selected == null) return;
    final text = _controller.text;
    final selection = _controller.selection;
    final cursor = selection.isValid ? selection.baseOffset : text.length;
    final before = text.substring(0, cursor);
    final after = text.substring(cursor);
    final shouldReplaceTrigger = before.endsWith('@');
    final prefix = shouldReplaceTrigger
        ? before.substring(0, before.length - 1)
        : before;
    final inserted = '@$selected ';
    _controller.value = TextEditingValue(
      text: '$prefix$inserted$after',
      selection: TextSelection.collapsed(
        offset: prefix.length + inserted.length,
      ),
    );
  }

  void _handleInputChanged(String value) {
    if (!value.endsWith('@')) {
      _lastMentionPopupLength = -1;
      return;
    }
    if (value.length == _lastMentionPopupLength) return;
    _lastMentionPopupLength = value.length;
    _showMentionPicker();
  }

  Future<void> _showMessageActions(GroupMessage message) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('回复'),
              onTap: () => Navigator.pop(context, 'reply'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('复制'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'reply') {
      setState(() => _replyingTo = message);
      _inputFocusNode.requestFocus();
    } else if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: message.content));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已复制')));
    }
  }

  GroupMessage? _messageById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final message in _messages) {
      if (message.id == id) return message;
    }
    return null;
  }

  String _senderName(GroupMessage message) {
    return switch (message.senderType) {
      GroupSenderType.user => '用户',
      GroupSenderType.character =>
        _characters[message.senderId]?.displayName ?? '群成员',
      GroupSenderType.system => '系统',
    };
  }

  bool _isCurrent(int generation) => mounted && generation == _replyGeneration;

  Future<void> _openSettings() async {
    final group = _group;
    if (group == null) return;
    _closeMorePanel();
    ++_replyGeneration;
    if (mounted) {
      setState(() {
        _replying = false;
        _typingCharacterId = null;
      });
    }
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => GroupChatSettingsPage(groupId: group.id),
      ),
    );
    if (!mounted) return;
    if (result == 'deleted') {
      Navigator.pop(context, true);
      return;
    }
    await _load();
  }

  void _scrollToBottom({Duration delay = Duration.zero}) {
    Future<void>.delayed(delay, () {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final group = _group;
    final typingCharacter = _typingCharacterId == null
        ? null
        : _characters[_typingCharacterId];
    final appearance = PeiLinkAppearanceScope.of(context);
    final bubbleTheme = effectiveBubbleTheme(context);
    final groupTopBar = PeiLinkThemeScope.of(context).groupTopBarTheme;
    // 系统返回键优先关闭扩展面板，再退出页面（与单聊一致）。
    return PopScope(
      canPop: !_showMorePanel,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeMorePanel();
      },
      child: ThemeBackgroundContainer(
        background: PeiLinkThemeScope.of(context).groupBackground,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: groupTopBar.background,
            foregroundColor: groupTopBar.foreground,
            surfaceTintColor: Colors.transparent,
            titleSpacing: 0,
            toolbarHeight: 44 + MediaQuery.textScalerOf(context).scale(14),
            // 主标题只放群名，人数降为副信息，避免标题被拼接过长。
            title: Row(
              children: [
                if (group != null)
                  GroupAvatar(
                    key: const ValueKey('group-header-avatar'),
                    size: 36,
                    customAvatarPath: group.avatarPath,
                    members: groupAvatarMembers(
                      userAvatarPath: _userAvatarPath,
                      characters: group.memberCharacterIds.map((id) {
                        final character = _characters[id];
                        return GroupAvatarMember(
                          id: id,
                          avatarPath:
                              character?.effectiveSocialAvatarPath ?? '',
                          isUser: false,
                        );
                      }),
                    ),
                  )
                else
                  const SizedBox(width: 36, height: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group?.name ?? '群聊',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF1B2028),
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (group != null)
                        Text(
                          '${group.members.length + 1} 人',
                          style: const TextStyle(
                            color: Color(0xFF8A9298),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                onPressed: group == null ? null : _openSettings,
                tooltip: '群聊设置',
                icon: const Icon(Icons.more_horiz_rounded),
              ),
            ],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : group == null
              ? const Center(child: Text('群聊不存在或已被删除'))
              : Column(
                  children: [
                    Expanded(
                      child: _messages.isEmpty
                          ? const _EmptyGroupHint()
                          : ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(14, 18, 14, 8),
                              itemCount: _messages.length,
                              itemBuilder: (context, index) {
                                final message = _messages[index];
                                final previous = index == 0
                                    ? null
                                    : _messages[index - 1];
                                final showTime =
                                    previous == null ||
                                    message.createdAt
                                            .difference(previous.createdAt)
                                            .inMinutes
                                            .abs() >=
                                        5;
                                final sameSender =
                                    previous != null &&
                                    previous.senderType == message.senderType &&
                                    previous.senderId == message.senderId &&
                                    message.createdAt
                                            .difference(previous.createdAt)
                                            .inMinutes
                                            .abs() <=
                                        3;
                                final quoted = _messageById(
                                  message.replyToMessageId,
                                );
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (showTime)
                                      _GroupTimeLabel(time: message.createdAt),
                                    _GroupMessageBubble(
                                      message: message,
                                      character: _characters[message.senderId],
                                      compact: sameSender && !showTime,
                                      quotedMessage: quoted,
                                      quotedSenderName: quoted == null
                                          ? null
                                          : _senderName(quoted),
                                      mentionNames: [
                                        '用户',
                                        '全体成员',
                                        ..._characters.values.expand(
                                          (character) => [
                                            character.displayName,
                                            character.characterName,
                                          ],
                                        ),
                                      ],
                                      bubbleTheme: bubbleTheme,
                                      fontTheme:
                                          appearance.fontTheme.effectiveFont,
                                      onLongPress: () =>
                                          _showMessageActions(message),
                                      onAvatarTap:
                                          message.senderType ==
                                              GroupSenderType.character
                                          ? () => _openMemberChat(
                                              message.senderId,
                                            )
                                          : null,
                                      onRetry:
                                          message.status ==
                                              GroupMessageStatus.failed
                                          ? () => _retryMessage(message)
                                          : null,
                                    ),
                                  ],
                                );
                              },
                            ),
                    ),
                    if (_replying) _TypingBar(character: typingCharacter),
                    SafeArea(
                      top: false,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.95),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(22),
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x0C7668A6),
                              blurRadius: 16,
                              offset: Offset(0, -3),
                            ),
                          ],
                          border: const Border(
                            top: BorderSide(color: Color(0xFFE9EEF1)),
                          ),
                        ),
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_replyingTo != null)
                              _ReplyComposerPreview(
                                senderName: _senderName(_replyingTo!),
                                content: _replyingTo!.content,
                                onClose: () =>
                                    setState(() => _replyingTo = null),
                              ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                // + 与单聊一致：就地展开/收起功能宫格（不弹 BottomSheet）。
                                IconButton(
                                  key: const ValueKey('group-extension-entry'),
                                  onPressed: _toggleMorePanel,
                                  tooltip: _showMorePanel ? '收起功能栏' : '更多功能',
                                  visualDensity: VisualDensity.compact,
                                  icon: AnimatedRotation(
                                    turns: _showMorePanel ? 0.125 : 0,
                                    duration: const Duration(milliseconds: 180),
                                    child: const Icon(
                                      Icons.add_circle_outline_rounded,
                                      size: 24,
                                      color: GroupVisuals.accent,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF6F8F9),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: const Color(0xFFE3EAEE),
                                      ),
                                    ),
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        // @ 作为输入框内左侧轻量图标，不再像孤立按钮。
                                        IconButton(
                                          key: const ValueKey(
                                            'group-mention-entry',
                                          ),
                                          onPressed: _showMentionPicker,
                                          visualDensity: VisualDensity.compact,
                                          tooltip: '@ 成员',
                                          icon: const Icon(
                                            Icons.alternate_email_rounded,
                                            size: 19,
                                            color: Color(0xFF8A9298),
                                          ),
                                        ),
                                        Expanded(
                                          child: TextField(
                                            controller: _controller,
                                            focusNode: _inputFocusNode,
                                            minLines: 1,
                                            maxLines: 5,
                                            textInputAction:
                                                TextInputAction.newline,
                                            onTap: _closeMorePanel,
                                            onChanged: _handleInputChanged,
                                            decoration: const InputDecoration(
                                              hintText: '发消息',
                                              isDense: true,
                                              border: InputBorder.none,
                                              contentPadding:
                                                  EdgeInsets.symmetric(
                                                    vertical: 11,
                                                  ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  height:
                                      24 +
                                      MediaQuery.textScalerOf(
                                        context,
                                      ).scale(16),
                                  child: FilledButton(
                                    onPressed: _send,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: GroupVisuals.accent,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      minimumSize: const Size(0, 36),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                    ),
                                    child: const Text('发送'),
                                  ),
                                ),
                              ],
                            ),
                            // 复用单聊的 AnimatedSize + ChatMorePanel 结构。
                            AnimatedSize(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              alignment: Alignment.topCenter,
                              child: _showMorePanel
                                  ? ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxHeight:
                                            (MediaQuery.sizeOf(context).height *
                                                    .34)
                                                .clamp(120.0, 270.0),
                                      ),
                                      child: SingleChildScrollView(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Divider(
                                              height: 1,
                                              color: Color(0xFFE2E2E2),
                                            ),
                                            ChatMorePanel(
                                              key: const ValueKey(
                                                'group-more-panel',
                                              ),
                                              closeOnSelection: false,
                                              highlightPersona: true,
                                              personaLabel: '我的群聊身份',
                                              disabledLabels: const [
                                                '相册',
                                                '红包',
                                                '让 Ta 换头像',
                                                '礼物',
                                                '文件',
                                                '虚拟定位',
                                                '音乐',
                                                '语音通话',
                                                '视频通话',
                                              ],
                                              onUserPersona: () {
                                                _closeMorePanel();
                                                _openGroupIdentity();
                                              },
                                              onPickImage: () {},
                                              onRedPacket: () {},
                                              onChangeAvatar: () {},
                                              onUnavailable: (_) {},
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
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

class _EmptyGroupHint extends StatelessWidget {
  const _EmptyGroupHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(22),
          decoration: GroupVisuals.card(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF9FC2D4), Color(0xFFB7AEE0)],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(color: Color(0x2279AFC8), blurRadius: 14),
                  ],
                ),
                child: const Icon(
                  Icons.forum_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '群聊已创建',
                style: TextStyle(
                  color: Color(0xFF4A5A64),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '说点什么，看看谁先接上话题。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF9AA5AB),
                  fontSize: 12.5,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypingBar extends StatelessWidget {
  const _TypingBar({required this.character});

  final AiCharacter? character;

  @override
  Widget build(BuildContext context) {
    final text = character == null
        ? '正在判断谁会回复…'
        : '${character!.displayName}正在输入…';
    return Container(
      width: double.infinity,
      color: const Color(0xF5F7F5FB),
      padding: const EdgeInsets.fromLTRB(64, 5, 14, 7),
      child: Text(
        text,
        style: const TextStyle(color: Color(0xFF6E6680), fontSize: 13),
      ),
    );
  }
}

class _GroupTimeLabel extends StatelessWidget {
  const _GroupTimeLabel({required this.time});

  final DateTime time;

  static String format(DateTime time) {
    final now = DateTime.now();
    final hm =
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
    final sameDay =
        now.year == time.year && now.month == time.month && now.day == time.day;
    if (sameDay) return hm;
    return '${time.month}月${time.day}日 $hm';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            format(time),
            style: const TextStyle(color: Color(0xFF626477), fontSize: 11),
          ),
        ),
      ),
    );
  }
}

class _GroupMessageBubble extends StatelessWidget {
  const _GroupMessageBubble({
    required this.message,
    required this.character,
    required this.compact,
    required this.quotedMessage,
    required this.quotedSenderName,
    required this.mentionNames,
    required this.bubbleTheme,
    required this.fontTheme,
    required this.onLongPress,
    this.onAvatarTap,
    this.onRetry,
  });

  final GroupMessage message;
  final AiCharacter? character;
  final bool compact;
  final GroupMessage? quotedMessage;
  final String? quotedSenderName;
  final List<String> mentionNames;
  final ChatBubbleTheme bubbleTheme;
  final ChatFontTheme fontTheme;
  final VoidCallback onLongPress;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    // 系统消息不套聊天气泡，保持中性系统提示。
    if (message.senderType == GroupSenderType.system) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xE6FFFFFF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              message.content,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF6B7075),
                fontSize: 11.5,
                height: 1.3,
              ),
            ),
          ),
        ),
      );
    }

    final isUser = message.senderType == GroupSenderType.user;
    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10, left: 52),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (message.status == GroupMessageStatus.failed) ...[
                InkWell(
                  onTap: onRetry,
                  key: ValueKey('group-message-retry-${message.id}'),
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.all(3),
                    child: Icon(
                      Icons.error_outline_rounded,
                      size: 17,
                      color: Color(0xFFD05252),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ] else if (message.status == GroupMessageStatus.sending) ...[
                const Padding(
                  padding: EdgeInsets.all(3),
                  child: SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 1.6),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: _Bubble(
                  content: message.content,
                  isUser: true,
                  quotedMessage: quotedMessage,
                  quotedSenderName: quotedSenderName,
                  mentionNames: mentionNames,
                  bubbleTheme: bubbleTheme,
                  fontTheme: fontTheme,
                  onLongPress: onLongPress,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 5 : 10, right: 42),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 42,
            child: compact
                ? const SizedBox.shrink()
                : GestureDetector(
                    onTap: onAvatarTap,
                    child: _CharacterAvatar(character: character),
                  ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!compact)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xE6FFFFFF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        character?.displayName ?? '群成员',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF5C5470),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                _Bubble(
                  content: message.content,
                  isUser: false,
                  quotedMessage: quotedMessage,
                  quotedSenderName: quotedSenderName,
                  mentionNames: mentionNames,
                  bubbleTheme: bubbleTheme,
                  fontTheme: fontTheme,
                  onLongPress: onLongPress,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.content,
    required this.isUser,
    required this.quotedMessage,
    required this.quotedSenderName,
    required this.mentionNames,
    required this.bubbleTheme,
    required this.fontTheme,
    required this.onLongPress,
  });

  final String content;
  final bool isUser;
  final GroupMessage? quotedMessage;
  final String? quotedSenderName;
  final List<String> mentionNames;
  final ChatBubbleTheme bubbleTheme;
  final ChatFontTheme fontTheme;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.68,
        ),
        // 复用单聊气泡外壳，跟随用户当前的 bubbleThemeId。
        child: ChatBubbleSurface(
          theme: bubbleTheme,
          isUser: isUser,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (quotedMessage != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 7),
                  padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        quotedSenderName ?? '群成员',
                        style: const TextStyle(
                          color: Color(0xFF3D7F9F),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        quotedMessage!.content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF666666),
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              _MentionText(
                content: content,
                mentionNames: mentionNames,
                fontTheme: fontTheme,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MentionText extends StatelessWidget {
  const _MentionText({
    required this.content,
    required this.mentionNames,
    required this.fontTheme,
  });

  final String content;
  final List<String> mentionNames;
  final ChatFontTheme fontTheme;

  /// 与单聊一致的代码块隔离规则，保证群聊里的 code 仍是 monospace。
  static final RegExp _code = RegExp(
    r'(```|~~~)[\s\S]*?(?:\1|$)|(`+)[^\n]*?\2',
  );

  TextStyle get _baseStyle => TextStyle(
    color: const Color(0xFF1F1F1F),
    fontSize: 16,
    height: 1.35,
    fontFamily: fontTheme.fontFamily,
    fontFamilyFallback: fontTheme.fontFamilyFallback,
    fontWeight: fontTheme.fontWeight,
  );

  @override
  Widget build(BuildContext context) {
    final names =
        mentionNames.where((name) => name.trim().isNotEmpty).toSet().toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    final hasCode = _code.hasMatch(content);
    if (names.isEmpty && !hasCode) {
      return Text(content, style: _baseStyle);
    }
    final pattern = names.isEmpty
        ? null
        : RegExp('@(?:${names.map(RegExp.escape).join('|')})');
    final spans = <TextSpan>[];
    void addPlain(String text) {
      if (text.isEmpty) return;
      if (pattern == null) {
        spans.add(TextSpan(text: text));
        return;
      }
      var cursor = 0;
      for (final match in pattern.allMatches(text)) {
        if (match.start > cursor) {
          spans.add(TextSpan(text: text.substring(cursor, match.start)));
        }
        spans.add(
          TextSpan(
            text: match.group(0),
            style: const TextStyle(
              color: Color(0xFF3D7F9F),
              fontWeight: FontWeight.w600,
            ),
          ),
        );
        cursor = match.end;
      }
      if (cursor < text.length) {
        spans.add(TextSpan(text: text.substring(cursor)));
      }
    }

    var cursor = 0;
    for (final match in _code.allMatches(content)) {
      if (match.start > cursor) {
        addPlain(content.substring(cursor, match.start));
      }
      spans.add(
        TextSpan(
          text: match.group(0),
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 16,
            height: 1.35,
            fontWeight: FontWeight.w400,
            color: Color(0xFF1F1F1F),
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < content.length) {
      addPlain(content.substring(cursor));
    }
    return Text.rich(TextSpan(style: _baseStyle, children: spans));
  }
}

class _ReplyComposerPreview extends StatelessWidget {
  const _ReplyComposerPreview({
    required this.senderName,
    required this.content,
    required this.onClose,
  });

  final String senderName;
  final String content;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.fromLTRB(10, 7, 4, 7),
      decoration: BoxDecoration(
        color: const Color(0xFFECECEC),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '回复 $senderName',
                  style: const TextStyle(
                    color: Color(0xFF4E8EAD),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF777777),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

class _CharacterAvatar extends StatelessWidget {
  const _CharacterAvatar({required this.character});

  final AiCharacter? character;

  @override
  Widget build(BuildContext context) {
    return PeiLinkThemedAvatar(
      size: 42,
      role: PeiLinkAvatarRole.character,
      imagePath: character?.effectiveSocialAvatarPath ?? '',
      frame: PeiLinkThemeScope.of(context).avatarFrameTheme.character,
      fallback: Text(
        (character?.displayName.trim().isNotEmpty == true
                ? character!.displayName.trim()[0]
                : '群')
            .toUpperCase(),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFF4E6A78),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
