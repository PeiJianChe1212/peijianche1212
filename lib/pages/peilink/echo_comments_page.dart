import 'package:flutter/material.dart';

import '../../models/ai_character.dart';
import '../../models/echo_item.dart';
import '../../models/user_profile.dart';
import '../../services/echo_comment_reply_service.dart';
import '../../services/echo_storage_service.dart';

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

  Future<void> _saveEcho(EchoItem updated) async {
    await EchoStorageService(characterId: widget.ownerId).updateItem(updated);
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
      authorType: EchoAuthorType.user,
      content: content,
      createdAt: now,
    );

    try {
      await _saveEcho(
        _echo.copyWith(comments: [..._echo.comments, comment]),
      );
      _controller.clear();
      _focusNode.unfocus();
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
      );
      final now = DateTime.now();
      final reply = EchoComment(
        id: 'comment_${now.microsecondsSinceEpoch}',
        authorType: EchoAuthorType.character,
        content: content,
        createdAt: now,
        replyToCommentId: comment.id,
      );
      await _saveEcho(
        _echo.copyWith(comments: [..._echo.comments, reply]),
      );
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
          comment.authorType == EchoAuthorType.character &&
          comment.replyToCommentId == commentId,
    );
  }

  Future<void> _deleteComment(EchoComment comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这条评论？'),
        content: comment.authorType == EchoAuthorType.user
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

    final next = _echo.comments.where((item) {
      if (item.id == comment.id) return false;
      if (comment.authorType == EchoAuthorType.user &&
          item.replyToCommentId == comment.id) {
        return false;
      }
      return true;
    }).toList();

    try {
      await _saveEcho(_echo.copyWith(comments: next));
    } catch (error) {
      _showMessage('删除失败：$error');
    }
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
                        characterName: _characterName,
                        isReplying: _replyingCommentId == comment.id,
                        canGenerateReply:
                            widget.character != null &&
                            comment.authorType == EchoAuthorType.user &&
                            !_hasReplyFor(comment.id),
                        onGenerateReply: () => _generateReply(comment),
                        onDelete: () => _deleteComment(comment),
                      ),
                ],
              ),
            ),
            _CommentComposer(
              controller: _controller,
              focusNode: _focusNode,
              saving: _saving,
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
    required this.characterName,
    required this.isReplying,
    required this.canGenerateReply,
    required this.onGenerateReply,
    required this.onDelete,
  });

  final EchoComment comment;
  final String userName;
  final String characterName;
  final bool isReplying;
  final bool canGenerateReply;
  final VoidCallback onGenerateReply;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isCharacter = comment.authorType == EchoAuthorType.character;
    final name = isCharacter
        ? (characterName.isEmpty ? '角色' : characterName)
        : userName;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                name,
                style: const TextStyle(
                  color: Color(0xFF576B95),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              if (isCharacter) ...[
                const SizedBox(width: 6),
                const Text(
                  '回复',
                  style: TextStyle(
                    color: Color(0xFF999999),
                    fontSize: 12,
                  ),
                ),
              ],
              const Spacer(),
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
          Text(
            comment.content,
            style: const TextStyle(
              color: Color(0xFF222222),
              fontSize: 14,
              height: 1.45,
            ),
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
    );
  }
}

class _CommentComposer extends StatelessWidget {
  const _CommentComposer({
    required this.controller,
    required this.focusNode,
    required this.saving,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool saving;
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
        child: Row(
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
      ),
    );
  }
}
