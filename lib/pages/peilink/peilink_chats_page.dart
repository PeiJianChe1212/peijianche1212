import 'dart:io';

import 'package:flutter/material.dart';

import '../../conversation/message_content_parser.dart';
import '../../models/ai_character.dart';
import '../../models/chat_message.dart';
import '../../models/character_settings.dart';
import '../../services/character_registry_service.dart';
import '../../services/character_settings_storage_service.dart';
import '../../services/chat_storage_service.dart';
import '../../services/initiative_service.dart';
import '../chat_page.dart';

class PeiLinkChatsPage extends StatefulWidget {
  const PeiLinkChatsPage({super.key});

  @override
  State<PeiLinkChatsPage> createState() => _PeiLinkChatsPageState();
}

class _PeiLinkChatsPageState extends State<PeiLinkChatsPage> {
  final CharacterRegistryService _registry = CharacterRegistryService();

  List<_ConversationPreview> _conversations = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadConversationPreviews();
  }

  Future<void> _loadConversationPreviews() async {
    try {
      final characters = await _registry.loadCharacters();
      final previews = <_ConversationPreview>[];

      for (final character in characters) {
        final messages = await ChatStorageService(
          characterId: character.id,
        ).loadMessages();
        final settings = await CharacterSettingsStorageService(
          characterId: character.id,
        ).loadSettings();
        final unread = await InitiativeService(
          characterId: character.id,
        ).unreadCount();

        previews.add(
          _ConversationPreview(
            character: character,
            settings: settings,
            lastMessage: messages.isEmpty ? null : messages.last,
            unreadCount: unread,
          ),
        );
      }

      previews.sort((a, b) {
        final aTime = a.lastMessage?.createdAt ?? a.character.createdAt;
        final bTime = b.lastMessage?.createdAt ?? b.character.createdAt;
        return bTime.compareTo(aTime);
      });

      if (!mounted) return;
      setState(() {
        _conversations = previews;
        _loading = false;
      });
    } catch (error) {
      debugPrint('PeiLink 消息列表加载失败：$error');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _openChat(_ConversationPreview preview) async {
    await _registry.setActiveCharacter(preview.character.id);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChatPage()),
    );
    await _loadConversationPreviews();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search_rounded,
                    color: Color(0xFFB7B7B7),
                    size: 22,
                  ),
                  SizedBox(width: 7),
                  Text(
                    '搜索',
                    style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              color: Colors.white,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _conversations.isEmpty
                      ? const Center(child: Text('还没有 AI 进入消息列表'))
                      : RefreshIndicator(
                          onRefresh: _loadConversationPreviews,
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: _conversations.length,
                            itemBuilder: (context, index) {
                              final preview = _conversations[index];
                              return _ConversationTile(
                                preview: preview,
                                onTap: () => _openChat(preview),
                              );
                            },
                          ),
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationPreview {
  const _ConversationPreview({
    required this.character,
    required this.settings,
    required this.lastMessage,
    required this.unreadCount,
  });

  final AiCharacter character;
  final CharacterSettings settings;
  final ChatMessage? lastMessage;
  final int unreadCount;

  String get previewText {
    final message = lastMessage;
    if (message == null) {
      return '你已与${settings.characterName}建立羁绊，开始聊天吧。';
    }

    switch (message.type) {
      case MessageType.image:
        return '[图片]';
      case MessageType.voice:
        return '[语音]';
      case MessageType.system:
        return '[系统消息]';
      case MessageType.card:
        return '[卡片]';
      case MessageType.text:
        final spoken = MessageContentParser.spokenText(message.content);
        if (spoken.isNotEmpty) return spoken.replaceAll('\n', ' ');
        return message.content.replaceAll('\n', ' ');
    }
  }

  String get timeText {
    final message = lastMessage;
    if (message == null) return '';

    final time = message.createdAt;
    final now = DateTime.now();
    final isToday =
        time.year == now.year && time.month == now.month && time.day == now.day;
    if (isToday) {
      return '${time.hour.toString().padLeft(2, '0')}:'
          '${time.minute.toString().padLeft(2, '0')}';
    }

    final yesterday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 1));
    final isYesterday =
        time.year == yesterday.year &&
        time.month == yesterday.month &&
        time.day == yesterday.day;
    if (isYesterday) return '昨天';
    return '${time.month}月${time.day}日';
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.preview,
    required this.onTap,
  });

  final _ConversationPreview preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final character = preview.character;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 78,
        child: Row(
          children: [
            const SizedBox(width: 16),
            Stack(
              clipBehavior: Clip.none,
              children: [
                _CharacterAvatar(character: character),
                if (preview.unreadCount > 0)
                  Positioned(
                    right: -7,
                    top: -7,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 20),
                      height: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFA5151),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        preview.unreadCount > 99
                            ? '99+'
                            : '${preview.unreadCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Container(
                height: double.infinity,
                padding: const EdgeInsets.only(right: 16),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Color(0xFFEDEDED), width: 0.7),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            character.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF171717),
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            preview.previewText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF999999),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (preview.timeText.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 10, bottom: 29),
                        child: Text(
                          preview.timeText,
                          style: const TextStyle(
                            color: Color(0xFFB2B2B2),
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
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
        borderRadius: BorderRadius.circular(7),
        child: Image.file(
          File(path),
          width: 54,
          height: 54,
          fit: BoxFit.cover,
        ),
      );
    }

    if (character.isBuiltIn) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Image.asset(
          'assets/images/pei_avatar.jpg',
          width: 54,
          height: 54,
          fit: BoxFit.cover,
          alignment: const Alignment(0, -0.15),
        ),
      );
    }


    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: const Color(0xFFE5EBEE),
        borderRadius: BorderRadius.circular(7),
      ),
      child: const Icon(
        Icons.auto_awesome_rounded,
        color: Color(0xFF647C8B),
      ),
    );
  }
}
