import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/ai_character.dart';
import '../../models/group_chat.dart';
import '../../models/group_message.dart';
import '../../services/character_registry_service.dart';
import '../../services/group_chat_storage_service.dart';
import '../../services/group_conversation_coordinator.dart';
import '../../services/group_message_storage_service.dart';
import 'group_chat_settings_page.dart';

class GroupChatPage extends StatefulWidget {
  const GroupChatPage({super.key, required this.groupId});

  final String groupId;

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> {
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _replyGeneration++;
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
    ]);
    if (!mounted) return;
    final characters = results[2] as List<AiCharacter>;
    setState(() {
      _group = results[0] as GroupChat?;
      _messages = results[1] as List<GroupMessage>;
      _characters = {
        for (final character in characters) character.id: character,
      };
      _loading = false;
    });
    _scrollToBottom();
  }

  Future<void> _send() async {
    final content = _controller.text.trim();
    final group = _group;
    if (content.isEmpty || group == null) return;

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
    await Future.wait([
      _messageStorage.saveMessages(updatedMessages),
      _groupStorage.upsertGroup(updatedGroup),
    ]);
    _scrollToBottom();
    unawaited(_runReplies(generation));
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
  }


  List<String> _extractMentionedIds(String content, GroupChat group) {
    final result = <String>{};
    if (content.contains('@全体成员') || content.contains('@所有人')) {
      result.addAll(group.memberCharacterIds);
    }
    if (content.contains('@林念念') || content.contains('@用户')) {
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
              const ListTile(
                title: Text('选择提醒的人'),
                dense: true,
              ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制')),
      );
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
      GroupSenderType.user => '林念念',
      GroupSenderType.character =>
        _characters[message.senderId]?.displayName ?? '群成员',
      GroupSenderType.system => '系统',
    };
  }

  bool _isCurrent(int generation) =>
      mounted && generation == _replyGeneration;

  Future<void> _openSettings() async {
    final group = _group;
    if (group == null) return;
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

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final group = _group;
    final typingCharacter = _typingCharacterId == null
        ? null
        : _characters[_typingCharacterId];
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F4F4),
        surfaceTintColor: Colors.transparent,
        title: Text(
          group == null ? '群聊' : '${group.name} (${group.members.length + 1})',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            onPressed: group == null ? null : _openSettings,
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
                                final sameSender = previous != null &&
                                    previous.senderType == message.senderType &&
                                    previous.senderId == message.senderId &&
                                    message.createdAt
                                            .difference(previous.createdAt)
                                            .inMinutes
                                            .abs() <=
                                        3;
                                final quoted =
                                    _messageById(message.replyToMessageId);
                                return _GroupMessageBubble(
                                  message: message,
                                  character: _characters[message.senderId],
                                  compact: sameSender,
                                  quotedMessage: quoted,
                                  quotedSenderName: quoted == null
                                      ? null
                                      : _senderName(quoted),
                                  mentionNames: [
                                    '林念念',
                                    '全体成员',
                                    ..._characters.values.expand((character) => [
                                          character.displayName,
                                          character.characterName,
                                        ]),
                                  ],
                                  onLongPress: () =>
                                      _showMessageActions(message),
                                );
                              },
                            ),
                    ),
                    if (_replying)
                      _TypingBar(character: typingCharacter),
                    SafeArea(
                      top: false,
                      child: Container(
                        color: const Color(0xFFF7F7F7),
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
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
                            IconButton(
                              onPressed: _showMentionPicker,
                              icon: const Icon(Icons.alternate_email_rounded),
                              color: const Color(0xFF777777),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                focusNode: _inputFocusNode,
                                minLines: 1,
                                maxLines: 5,
                                textInputAction: TextInputAction.newline,
                                onChanged: _handleInputChanged,
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: Colors.white,
                                  hintText: '发消息',
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 9,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              height: 40,
                              child: FilledButton(
                                onPressed: _send,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF4E8EAD),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                ),
                                child: const Text('发送'),
                              ),
                            ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _EmptyGroupHint extends StatelessWidget {
  const _EmptyGroupHint();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          '群聊已经创建。\n发一条消息，看看谁会先接话。',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF999999), height: 1.6),
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
      color: const Color(0xFFF2F2F2),
      padding: const EdgeInsets.fromLTRB(64, 5, 14, 7),
      child: Text(
        text,
        style: const TextStyle(color: Color(0xFF8C8C8C), fontSize: 13),
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
    required this.onLongPress,
  });

  final GroupMessage message;
  final AiCharacter? character;
  final bool compact;
  final GroupMessage? quotedMessage;
  final String? quotedSenderName;
  final List<String> mentionNames;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final isUser = message.senderType == GroupSenderType.user;
    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10, left: 52),
          child: _Bubble(
            content: message.content,
            isUser: true,
            quotedMessage: quotedMessage,
            quotedSenderName: quotedSenderName,
            mentionNames: mentionNames,
            onLongPress: onLongPress,
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
                : _CharacterAvatar(character: character),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!compact)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      character?.displayName ?? '群成员',
                      style: const TextStyle(
                        color: Color(0xFF777777),
                        fontSize: 12,
                      ),
                    ),
                  ),
                _Bubble(
                  content: message.content,
                  isUser: false,
                  quotedMessage: quotedMessage,
                  quotedSenderName: quotedSenderName,
                  mentionNames: mentionNames,
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
    required this.onLongPress,
  });

  final String content;
  final bool isUser;
  final GroupMessage? quotedMessage;
  final String? quotedSenderName;
  final List<String> mentionNames;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.68,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF95C47A) : Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (quotedMessage != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 7),
                padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      quotedSenderName ?? '群成员',
                      style: const TextStyle(
                        color: Color(0xFF4E8EAD),
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
            _MentionText(content: content, mentionNames: mentionNames),
          ],
        ),
      ),
    );
  }
}

class _MentionText extends StatelessWidget {
  const _MentionText({required this.content, required this.mentionNames});

  final String content;
  final List<String> mentionNames;

  @override
  Widget build(BuildContext context) {
    final names = mentionNames
        .where((name) => name.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    if (names.isEmpty) {
      return Text(content, style: _baseStyle);
    }
    final pattern = RegExp(
      '@(?:${names.map(RegExp.escape).join('|')})',
    );
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in pattern.allMatches(content)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: content.substring(cursor, match.start)));
      }
      spans.add(TextSpan(
        text: match.group(0),
        style: const TextStyle(
          color: Color(0xFF3D7F9F),
          fontWeight: FontWeight.w600,
        ),
      ));
      cursor = match.end;
    }
    if (cursor < content.length) {
      spans.add(TextSpan(text: content.substring(cursor)));
    }
    return Text.rich(TextSpan(style: _baseStyle, children: spans));
  }

  static const TextStyle _baseStyle = TextStyle(
    color: Color(0xFF1F1F1F),
    fontSize: 16,
    height: 1.35,
  );
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
    final path = character?.avatarPath.trim() ?? '';
    final file = path.isEmpty ? null : File(path);
    final exists = file?.existsSync() == true;
    return CircleAvatar(
      radius: 21,
      backgroundColor: const Color(0xFFD9E4EA),
      backgroundImage: exists ? FileImage(file!) : null,
      child: exists
          ? null
          : Text(
              (character?.displayName.trim().isNotEmpty == true
                      ? character!.displayName.trim()[0]
                      : '群')
                  .toUpperCase(),
              style: const TextStyle(
                color: Color(0xFF4E6A78),
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}
