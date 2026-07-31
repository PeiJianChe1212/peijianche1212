import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/ai_character.dart';
import '../../models/echo_item.dart';
import '../../models/echo_comment.dart';
import '../../models/user_profile.dart';
import '../../services/echo_comment_reply_service.dart';
import '../../services/auto_echo_comment_reply_service.dart';
import '../../services/echo_comment_storage_service.dart';
import '../../services/echo_comment_interaction_service.dart';
import '../../services/character_registry_service.dart';

class EchoCommentsPage extends StatefulWidget {
  const EchoCommentsPage({
    super.key,
    required this.ownerId,
    required this.echo,
    required this.userProfile,
    this.character,
  });

  final String ownerId;
  final EchoItem echo;
  final UserProfile userProfile;
  final AiCharacter? character;

  @override
  State<EchoCommentsPage> createState() => _EchoCommentsPageState();
}

class _EchoCommentsPageState extends State<EchoCommentsPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  late EchoItem _echo;
  EchoCommentReplyService? _replyService;
  bool _saving = false;
  String? _replyingCommentId;
  EchoComment? _replyingTo;

  String get _userName {
    final nickname = widget.userProfile.nickname.trim();
    return nickname.isEmpty ? '我' : nickname;
  }

  String get _characterName => widget.character?.characterName ?? '';

  @override
  void initState() {
    super.initState();
    _echo = widget.echo;
    final character = widget.character;
    if (character != null) {
      _replyService = EchoCommentReplyService(character: character);
    }
  }

  @override
  void dispose() {
    _replyService?.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _setEcho(EchoItem updated) async {
    if (!mounted) return;
    setState(() => _echo = updated);
  }

  Future<void> _submitComment() async {
    if (_saving) return;
    final content = _controller.text.trim();
    if (content.isEmpty) return;

    setState(() => _saving = true);
    final now = DateTime.now();
    final comment = EchoComment(
      id: 'comment_${now.microsecondsSinceEpoch}',
      echoId: _echo.id,
      authorType: EchoCommentAuthorType.user,
      authorId: 'peilink_user',
      authorNameSnapshot: _userName,
      authorAvatarSnapshot: widget.userProfile.avatarPath,
      content: content,
      createdAt: now,
      replyToCommentId: _replyingTo?.id,
      replyToAuthorId: _replyingTo?.authorId ?? '',
      replyToAuthorNameSnapshot:
          _replyingTo?.authorNameSnapshot ?? '',
      sourceType: EchoCommentSourceType.manualUser,
    );

    try {
      await EchoCommentStorageService(ownerId: widget.ownerId).add(comment);
      await EchoCommentInteractionService().record(
        echo: _echo,
        comment: comment,
        parentComment: _replyingTo,
      );
      await AutoEchoCommentReplyService().scheduleFor(
        echo: _echo,
        comment: comment,
        now: now,
      );
      await _setEcho(_echo.copyWith(comments: [..._echo.comments, comment]));
      _controller.clear();
      _focusNode.unfocus();
      setState(() => _replyingTo = null);
    } catch (error) {
      _showMessage('评论保存失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _generateReply(EchoComment comment) async {
    final service = _replyService;
    if (service == null || _replyingCommentId != null) return;

    setState(() => _replyingCommentId = comment.id);
    try {
      final content = await service.generateReply(
        echo: _echo,
        userComment: comment,
        existingComments: _echo.comments,
      );
      final now = DateTime.now();
      final character = widget.character!;
      final reply = EchoComment(
        id: 'comment_${now.microsecondsSinceEpoch}',
        echoId: _echo.id,
        authorType: EchoCommentAuthorType.character,
        content: content,
        createdAt: now,
        replyToCommentId: comment.id,
        replyToAuthorId: comment.authorId,
        replyToAuthorNameSnapshot: comment.authorNameSnapshot,
        authorId: character.id,
        authorNameSnapshot: character.displayName,
        authorAvatarSnapshot: character.avatarPath,
        sourceType: EchoCommentSourceType.autoReply,
      );
      await EchoCommentStorageService(ownerId: widget.ownerId).add(reply);
      await EchoCommentInteractionService().record(
        echo: _echo,
        comment: reply,
        parentComment: comment,
      );
      await _setEcho(_echo.copyWith(comments: [..._echo.comments, reply]));
    } catch (error) {
      _showMessage(
        error.toString().replaceFirst('Bad state: ', ''),
      );
    } finally {
      if (mounted) setState(() => _replyingCommentId = null);
    }
  }

  bool _hasReplyFor(String commentId) {
    return _echo.comments.any(
      (comment) =>
          comment.authorType == EchoCommentAuthorType.character &&
          comment.replyToCommentId == commentId,
    );
  }

  Future<void> _deleteComment(EchoComment comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这条评论？'),
        content: comment.authorType == EchoCommentAuthorType.user
            ? const Text('与它关联的角色回复也会一起删除。')
            : null,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              '删除',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await EchoCommentStorageService(ownerId: widget.ownerId).delete(
        comment.id,
        deleteReplies: true,
      );
      final next = _echo.comments
          .where(
            (item) =>
                item.id != comment.id &&
                item.replyToCommentId != comment.id,
          )
          .toList();
      await _setEcho(_echo.copyWith(comments: next));
    } catch (error) {
      _showMessage('删除失败：$error');
    }
  }

  Future<void> _addDebugCharacterComment() async {
    final characters = await CharacterRegistryService().loadCharacters();
    if (!mounted || characters.isEmpty) {
      _showMessage('还没有可用于调试的角色。');
      return;
    }
    final character = await showModalBottomSheet<AiCharacter>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('选择评论身份'),
              subtitle: Text('仅用于测试角色名、头像、回复与存储'),
            ),
            for (final item in characters)
              ListTile(
                title: Text(item.displayName),
                subtitle: Text(item.characterName),
                onTap: () => Navigator.pop(sheetContext, item),
              ),
          ],
        ),
      ),
    );
    if (character == null || !mounted) return;

    final input = TextEditingController();
    final content = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('以 ${character.displayName} 评论'),
        content: TextField(
          controller: input,
          autofocus: true,
          minLines: 1,
          maxLines: 4,
          maxLength: 500,
          decoration: const InputDecoration(hintText: '输入调试评论'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, input.text.trim()),
            child: const Text('发布'),
          ),
        ],
      ),
    );
    input.dispose();
    if (content == null || content.isEmpty) return;

    final now = DateTime.now();
    final comment = EchoComment(
      id: 'debug_comment_${now.microsecondsSinceEpoch}',
      echoId: _echo.id,
      authorType: EchoCommentAuthorType.character,
      authorId: character.id,
      authorNameSnapshot: character.displayName,
      authorAvatarSnapshot: character.avatarPath,
      content: content,
      createdAt: now,
      sourceType: EchoCommentSourceType.manualCharacterDebug,
    );
    await EchoCommentStorageService(ownerId: widget.ownerId).add(comment);
    await _setEcho(_echo.copyWith(comments: [..._echo.comments, comment]));
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F4F1),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF5F4F1),
          surfaceTintColor: Colors.transparent,
          title: const Text(
            '评论',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: '角色评论调试',
              onPressed: _addDebugCharacterComment,
              icon: const Icon(Icons.bug_report_outlined),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  _EchoSummary(
                    authorName: widget.character?.characterName ?? _userName,
                    content: _echo.content,
                  ),
                  const SizedBox(height: 14),
                  if (_echo.comments.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 54),
                      child: Center(
                        child: Text(
                          '还没有评论。',
                          style: TextStyle(color: Color(0xFFAAAAAA)),
                        ),
                      ),
                    )
                  else
                    for (final comment in _echo.comments)
                      _CommentTile(
                        comment: comment,
                        userName: _userName,
                        userAvatarPath: widget.userProfile.avatarPath,
                        characterName: _characterName,
                        characterAvatarPath:
                            widget.character?.avatarPath ?? '',
                        isReplying: _replyingCommentId == comment.id,
                        canGenerateReply:
                            widget.character != null &&
                            comment.authorType ==
                                EchoCommentAuthorType.user &&
                            !_hasReplyFor(comment.id),
                        onGenerateReply: () => _generateReply(comment),
                        onReply: () {
                          setState(() => _replyingTo = comment);
                          _focusNode.requestFocus();
                        },
                        onDelete: () => _deleteComment(comment),
                      ),
                ],
              ),
            ),
            _CommentComposer(
              controller: _controller,
              focusNode: _focusNode,
              saving: _saving,
              replyingToName: _replyingTo?.authorNameSnapshot ?? '',
              onCancelReply: () => setState(() => _replyingTo = null),
              onSubmit: _submitComment,
            ),
          ],
        ),
      ),
    );
  }
}

class _EchoSummary extends StatelessWidget {
  const _EchoSummary({
    required this.authorName,
    required this.content,
  });

  final String authorName;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            authorName,
            style: const TextStyle(
              color: Color(0xFF576B95),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            content.trim().isEmpty ? '图片动态' : content,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF333333),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.userName,
    required this.userAvatarPath,
    required this.characterName,
    required this.characterAvatarPath,
    required this.isReplying,
    required this.canGenerateReply,
    required this.onGenerateReply,
    required this.onReply,
    required this.onDelete,
  });

  final EchoComment comment;
  final String userName;
  final String userAvatarPath;
  final String characterName;
  final String characterAvatarPath;
  final bool isReplying;
  final bool canGenerateReply;
  final VoidCallback onGenerateReply;
  final VoidCallback onReply;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isCharacter =
        comment.authorType == EchoCommentAuthorType.character;
    final savedName = comment.authorNameSnapshot.trim();
    final name = isCharacter
        ? (savedName.isNotEmpty
            ? savedName
            : (characterName.isEmpty ? '角色' : characterName))
        : userName;
    final savedAvatar = comment.authorAvatarSnapshot.trim();
    final avatarPath = isCharacter
        ? (savedAvatar.isNotEmpty ? savedAvatar : characterAvatarPath.trim())
        : userAvatarPath.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CommentAvatar(
            path: avatarPath,
            fallbackName: name,
            isCharacter: isCharacter,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF576B95),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: '删除',
                      onPressed: onDelete,
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 17,
                        color: Color(0xFFAAAAAA),
                      ),
                    ),
                  ],
                ),
                Text.rich(
                  TextSpan(
                    children: [
                      if (comment.replyToAuthorNameSnapshot
                          .trim()
                          .isNotEmpty) ...[
                        const TextSpan(text: '回复 '),
                        TextSpan(
                          text: comment.replyToAuthorNameSnapshot.trim(),
                          style: const TextStyle(
                            color: Color(0xFF576B95),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const TextSpan(text: '：'),
                      ],
                      TextSpan(text: comment.content),
                    ],
                  ),
                  style: const TextStyle(
                    color: Color(0xFF222222),
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                TextButton(
                  onPressed: onReply,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('回复'),
                ),
                if (canGenerateReply) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: isReplying ? null : onGenerateReply,
                    icon: isReplying
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome_outlined, size: 17),
                    label: Text(isReplying ? '正在回复…' : '让角色回复'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentAvatar extends StatelessWidget {
  const _CommentAvatar({
    required this.path,
    required this.fallbackName,
    required this.isCharacter,
  });

  final String path;
  final String fallbackName;
  final bool isCharacter;

  @override
  Widget build(BuildContext context) {
    final file = path.isEmpty ? null : File(path);
    final hasFile = file != null && file.existsSync();
    final fallback = fallbackName.trim().isEmpty
        ? (isCharacter ? '角' : '我')
        : fallbackName.trim().substring(0, 1);

    return ClipOval(
      child: Container(
        width: 38,
        height: 38,
        color: const Color(0xFFE8E8E8),
        alignment: Alignment.center,
        child: hasFile
            ? Image.file(
                file,
                width: 38,
                height: 38,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Text(
                  fallback,
                  style: const TextStyle(
                    color: Color(0xFF777777),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            : Text(
                fallback,
                style: const TextStyle(
                  color: Color(0xFF777777),
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}

class _CommentComposer extends StatelessWidget {
  const _CommentComposer({
    required this.controller,
    required this.focusNode,
    required this.saving,
    required this.replyingToName,
    required this.onCancelReply,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool saving;
  final String replyingToName;
  final VoidCallback onCancelReply;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Color(0xFFE5E5E5)),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (replyingToName.trim().isNotEmpty)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '回复 ${replyingToName.trim()}',
                      style: const TextStyle(
                        color: Color(0xFF777777),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: onCancelReply,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 17),
                  ),
                ],
              ),
            Row(
              children: [
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                minLines: 1,
                maxLines: 4,
                maxLength: 500,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: '写下评论…',
                  counterText: '',
                  filled: true,
                  fillColor: const Color(0xFFF3F4F6),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: saving ? null : onSubmit,
              icon: saving
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.arrow_upward_rounded),
            ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
