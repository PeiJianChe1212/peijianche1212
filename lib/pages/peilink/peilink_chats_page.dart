import 'dart:io';

import 'package:flutter/material.dart';

import '../../conversation/message_content_parser.dart';
import '../../models/ai_character.dart';
import '../../models/chat_message.dart';
import '../../models/character_settings.dart';
import '../../models/group_chat.dart';
import '../../services/character_registry_service.dart';
import '../../services/character_settings_storage_service.dart';
import '../../services/chat_storage_service.dart';
import '../../services/initiative_service.dart';
import '../../services/group_chat_storage_service.dart';
import '../../theme/app_dimensions.dart';
import '../../theme/app_theme_background.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/peilink/relationship_badge.dart';
import '../chat_page.dart';
import 'group_chat_page.dart';

class PeiLinkChatsPage extends StatefulWidget {
  const PeiLinkChatsPage({super.key});

  @override
  State<PeiLinkChatsPage> createState() => _PeiLinkChatsPageState();
}

class _PeiLinkChatsPageState extends State<PeiLinkChatsPage> {
  final CharacterRegistryService _registry = CharacterRegistryService();
  final GroupChatStorageService _groupStorage = GroupChatStorageService();

  List<_ConversationPreview> _conversations = const [];
  List<GroupChat> _groups = const [];
  Map<String, AiCharacter> _charactersById = const {};
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
      final groups = await _groupStorage.loadGroups();

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

      groups.sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return b.lastActiveAt.compareTo(a.lastActiveAt);
      });

      if (!mounted) return;
      setState(() {
        _conversations = previews;
        _groups = groups;
        _charactersById = {for (final item in characters) item.id: item};
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

  Future<void> _openGroup(GroupChat group) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GroupChatPage(groupId: group.id)),
    );
    await _loadConversationPreviews();
  }

  @override
  Widget build(BuildContext context) {
    return ThemeBackgroundContainer(
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                14,
                AppSpacing.xs,
                14,
                AppSpacing.sm,
              ),
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.search_rounded,
                      color: Color(0xFFB7B7B7),
                      size: 19,
                    ),
                    SizedBox(width: 7),
                    Text(
                      '搜索',
                      style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ColoredBox(
                color: Colors.transparent,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _conversations.isEmpty && _groups.isEmpty
                    ? const Center(child: Text('还没有聊天，点右上角“+”开始吧'))
                    : RefreshIndicator(
                        onRefresh: _loadConversationPreviews,
                        child: ListView(
                          padding: const EdgeInsets.only(bottom: 84),
                          children: [
                            for (final group in _groups)
                              _GroupConversationTile(
                                group: group,
                                charactersById: _charactersById,
                                onTap: () => _openGroup(group),
                              ),
                            for (final preview in _conversations)
                              _ConversationTile(
                                preview: preview,
                                onTap: () => _openChat(preview),
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
      case MessageType.redPacket:
        return '[消息]';
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
  const _ConversationTile({required this.preview, required this.onTap});

  final _ConversationPreview preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final character = preview.character;
    final relationshipText = RelationshipBadge.displayTextFor(
      character.relationship,
    );
    return _GlassConversationCard(
      onTap: onTap,
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            const SizedBox(width: AppSpacing.lg),
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
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Container(
                height: double.infinity,
                padding: const EdgeInsets.only(right: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  character.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.listTitle.copyWith(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              const _StatusMark(label: 'AI · 在线'),
                            ],
                          ),
                          if (relationshipText != null) ...[
                            const SizedBox(height: 1),
                            RelationshipBadge(
                              relationship: character.relationship,
                            ),
                          ],
                          const SizedBox(height: 2),
                          Text(
                            preview.previewText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.supporting.copyWith(
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (preview.timeText.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 10, bottom: 24),
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
          width: AppDimensions.avatarMedium,
          height: AppDimensions.avatarMedium,
          fit: BoxFit.cover,
        ),
      );
    }

    if (character.isBuiltIn) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Image.asset(
          'assets/images/pei_avatar.jpg',
          width: AppDimensions.avatarMedium,
          height: AppDimensions.avatarMedium,
          fit: BoxFit.cover,
          alignment: const Alignment(0, -0.15),
        ),
      );
    }

    return Container(
      width: AppDimensions.avatarMedium,
      height: AppDimensions.avatarMedium,
      decoration: BoxDecoration(
        color: const Color(0xFFE5EBEE),
        borderRadius: BorderRadius.circular(7),
      ),
      child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF647C8B)),
    );
  }
}

class _GroupConversationTile extends StatelessWidget {
  const _GroupConversationTile({
    required this.group,
    required this.charactersById,
    required this.onTap,
  });

  final GroupChat group;
  final Map<String, AiCharacter> charactersById;
  final VoidCallback onTap;

  String get _timeText {
    final time = group.lastMessageAt;
    if (time == null) return '';
    final now = DateTime.now();
    final isToday =
        time.year == now.year && time.month == now.month && time.day == now.day;
    if (isToday) {
      return '${time.hour.toString().padLeft(2, '0')}:'
          '${time.minute.toString().padLeft(2, '0')}';
    }
    return '${time.month}月${time.day}日';
  }

  @override
  Widget build(BuildContext context) {
    final members = group.memberCharacterIds
        .map((id) => charactersById[id])
        .whereType<AiCharacter>()
        .toList();
    return _GlassConversationCard(
      onTap: onTap,
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            const SizedBox(width: 16),
            Stack(
              clipBehavior: Clip.none,
              children: [
                _GroupAvatar(characters: members),
                if (group.unreadCount > 0 && !group.isMuted)
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
                        group.unreadCount > 99 ? '99+' : '${group.unreadCount}',
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
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (group.isPinned)
                                const Padding(
                                  padding: EdgeInsets.only(right: 4),
                                  child: Icon(
                                    Icons.push_pin_rounded,
                                    size: 14,
                                    color: Color(0xFF999999),
                                  ),
                                ),
                              Expanded(
                                child: Text(
                                  group.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF171717),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (group.isMuted)
                                const Icon(
                                  Icons.notifications_off_outlined,
                                  size: 16,
                                  color: Color(0xFFAAAAAA),
                                ),
                              const SizedBox(width: 6),
                              const _StatusMark(label: '群聊'),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            group.lastMessage.isEmpty
                                ? '群聊已创建'
                                : group.lastMessage.replaceAll('\n', ' '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF999999),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_timeText.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 10, bottom: 24),
                        child: Text(
                          _timeText,
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

class _GlassConversationCard extends StatelessWidget {
  const _GlassConversationCard({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7),
      child: Semantics(
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: child,
        ),
      ),
    );
  }
}

class _StatusMark extends StatelessWidget {
  const _StatusMark({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFDCECF2).withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(AppDimensions.radiusPill),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF52788A),
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _GroupAvatar extends StatelessWidget {
  const _GroupAvatar({required this.characters});

  final List<AiCharacter> characters;

  @override
  Widget build(BuildContext context) {
    final visible = characters.take(4).toList();
    return Container(
      width: AppDimensions.avatarMedium,
      height: AppDimensions.avatarMedium,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xFFE1E5E7),
        borderRadius: BorderRadius.circular(7),
      ),
      child: GridView.count(
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        children: [
          for (final character in visible) _MiniAvatar(character: character),
          for (var i = visible.length; i < 4; i++)
            Container(color: const Color(0xFFF2F4F5)),
        ],
      ),
    );
  }
}

class _MiniAvatar extends StatelessWidget {
  const _MiniAvatar({required this.character});

  final AiCharacter character;

  @override
  Widget build(BuildContext context) {
    final path = character.avatarPath.trim();
    if (path.isNotEmpty && File(path).existsSync()) {
      return Image.file(File(path), fit: BoxFit.cover);
    }
    if (character.isBuiltIn) {
      return Image.asset('assets/images/pei_avatar.jpg', fit: BoxFit.cover);
    }
    return Container(
      color: const Color(0xFFEDF1F3),
      child: const Icon(
        Icons.auto_awesome_rounded,
        size: 13,
        color: Color(0xFF647C8B),
      ),
    );
  }
}
