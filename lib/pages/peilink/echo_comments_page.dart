import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/ai_character.dart';
import '../../models/echo_item.dart';
import '../../models/echo_comment.dart';
import '../../models/echo_interaction_stats.dart';
import '../../models/user_profile.dart';
import '../../services/echo_comment_reply_service.dart';
import '../../services/auto_echo_comment_reply_service.dart';
import '../../services/echo_comment_storage_service.dart';
import '../../services/echo_comment_interaction_service.dart';
import '../../services/echo_comment_reaction_storage_service.dart';
import '../../widgets/echo/ai_verified_badge.dart';

class EchoCommentsPage extends StatefulWidget {
  const EchoCommentsPage({
    super.key,
    required this.ownerId,
    required this.echo,
    required this.userProfile,
    this.interactionStats,
    this.character,
  });

  final String ownerId;
  final EchoItem echo;
  final UserProfile userProfile;
  final EchoInteractionStats? interactionStats;
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
  Map<String, int> _commentLikes = const {};

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
    _loadCommentLikes();
  }

  Future<void> _loadCommentLikes() async {
    final likes = await EchoCommentReactionStorageService(
      ownerId: widget.ownerId,
    ).loadLikes();
    if (mounted) setState(() => _commentLikes = likes);
  }

  Future<void> _toggleCommentLike(EchoComment comment) async {
    final likes = await EchoCommentReactionStorageService(
      ownerId: widget.ownerId,
    ).toggle(comment.id);
    if (mounted) setState(() => _commentLikes = likes);
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
      replyToAuthorNameSnapshot: _replyingTo?.authorNameSnapshot ?? '',
      sourceType: EchoCommentSourceType.manualUser,
      commentType: EchoCommentType.real,
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
        commentType: EchoCommentType.aiCharacter,
      );
      await EchoCommentStorageService(ownerId: widget.ownerId).add(reply);
      await EchoCommentInteractionService().record(
        echo: _echo,
        comment: reply,
        parentComment: comment,
      );
      await _setEcho(_echo.copyWith(comments: [..._echo.comments, reply]));
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Bad state: ', ''));
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
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await EchoCommentStorageService(
        ownerId: widget.ownerId,
      ).delete(comment.id, deleteReplies: true);
      final next = _echo.comments
          .where(
            (item) =>
                item.id != comment.id && item.replyToCommentId != comment.id,
          )
          .toList();
      await _setEcho(_echo.copyWith(comments: next));
    } catch (error) {
      _showMessage('删除失败：$error');
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final displayedCommentCount =
        _echo.comments.length > (widget.interactionStats?.commentCount ?? 0)
        ? _echo.comments.length
        : (widget.interactionStats?.commentCount ?? 0);
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFE8EEF2),
        appBar: AppBar(
          backgroundColor: Colors.white.withValues(alpha: 0.62),
          surfaceTintColor: Colors.transparent,
          title: const Text(
            '评论',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          centerTitle: true,
        ),
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFDDE7ED), Color(0xFFF8EDEA), Color(0xFFE8EEF3)],
            ),
          ),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                  children: [
                    _EchoSummary(
                      authorName: widget.character?.characterName ?? _userName,
                      authorAvatarPath:
                          widget.character?.avatarPath ??
                          widget.userProfile.avatarPath,
                      isCharacter: widget.character != null,
                      content: _echo.content,
                      imagePaths: _echo.imagePaths,
                      createdAt: _echo.createdAt,
                    ),
                    const SizedBox(height: 12),
                    _DetailInteractionBar(
                      viewCount: widget.interactionStats?.viewCount ?? 0,
                      likeCount:
                          (widget.interactionStats?.likeCount ?? 0) +
                          _echo.likeCount,
                      commentCount: displayedCommentCount,
                      collectCount:
                          (widget.interactionStats?.collectCount ?? 0) +
                          (_echo.isCollected ? 1 : 0),
                      onShare: () => _showMessage('分享功能敬请期待'),
                    ),
                    const SizedBox(height: 12),
                    _GlassSection(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '评论 $displayedCommentCount',
                            style: const TextStyle(
                              color: Color(0xFF3E4C55),
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_echo.comments.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 38),
                              child: Center(
                                child: Text(
                                  '暂时没有可展开的评论。\n世界的回应会留在这里。',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Color(0xFF929CA2),
                                    height: 1.55,
                                  ),
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
                                isAuthor: comment.authorId == widget.ownerId,
                                likeCount:
                                    (int.tryParse(
                                          comment.metadata['virtualLikeCount']
                                                  ?.toString() ??
                                              '',
                                        ) ??
                                        0) +
                                    (_commentLikes[comment.id] ?? 0),
                                isReplying: _replyingCommentId == comment.id,
                                canGenerateReply:
                                    widget.character != null &&
                                    comment.authorType ==
                                        EchoCommentAuthorType.user &&
                                    !_hasReplyFor(comment.id),
                                onLike: () => _toggleCommentLike(comment),
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
      ),
    );
  }
}

class _EchoSummary extends StatelessWidget {
  const _EchoSummary({
    required this.authorName,
    required this.authorAvatarPath,
    required this.isCharacter,
    required this.content,
    required this.imagePaths,
    required this.createdAt,
  });

  final String authorName;
  final String authorAvatarPath;
  final bool isCharacter;
  final String content;
  final List<String> imagePaths;
  final DateTime createdAt;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.62)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CommentAvatar(
                path: authorAvatarPath,
                fallbackName: authorName,
                isCharacter: isCharacter,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            authorName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF334A58),
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (isCharacter) ...[
                          const SizedBox(width: 6),
                          const AiVerifiedBadge(size: 14),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_detailTime(createdAt)}留下了一段 Echo',
                      style: const TextStyle(
                        color: Color(0xFF8B979E),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.more_horiz_rounded, color: Color(0xFF96A2A8)),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '📍 地点待记录   ·   ☁️ 生活状态待同步',
            style: TextStyle(color: Color(0xFF748792), fontSize: 11),
          ),
          const SizedBox(height: 13),
          Text(
            content.trim().isEmpty ? '图片动态' : content,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF333333), height: 1.45),
          ),
          if (imagePaths.isNotEmpty && File(imagePaths.first).existsSync()) ...[
            const SizedBox(height: 13),
            ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: Image.file(File(imagePaths.first), fit: BoxFit.cover),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GlassSection extends StatelessWidget {
  const _GlassSection({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white.withValues(alpha: 0.62)),
    ),
    child: child,
  );
}

class _DetailInteractionBar extends StatelessWidget {
  const _DetailInteractionBar({
    required this.viewCount,
    required this.likeCount,
    required this.commentCount,
    required this.collectCount,
    required this.onShare,
  });
  final int viewCount;
  final int likeCount;
  final int commentCount;
  final int collectCount;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) => _GlassSection(
    child: Row(
      children: [
        _DetailMetric(icon: Icons.visibility_outlined, value: '$viewCount'),
        _DetailMetric(
          icon: Icons.favorite_rounded,
          value: '$likeCount',
          active: true,
        ),
        _DetailMetric(
          icon: Icons.chat_bubble_outline_rounded,
          value: '$commentCount',
        ),
        _DetailMetric(icon: Icons.star_border_rounded, value: '$collectCount'),
        Expanded(
          child: IconButton(
            tooltip: '分享',
            onPressed: onShare,
            icon: const Icon(
              Icons.ios_share_rounded,
              color: Color(0xFF748993),
              size: 20,
            ),
          ),
        ),
      ],
    ),
  );
}

class _DetailMetric extends StatelessWidget {
  const _DetailMetric({
    required this.icon,
    required this.value,
    this.active = false,
  });
  final IconData icon;
  final String value;
  final bool active;
  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFFE4869C) : const Color(0xFF748993);
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
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
    required this.isAuthor,
    required this.likeCount,
    required this.isReplying,
    required this.canGenerateReply,
    required this.onGenerateReply,
    required this.onLike,
    required this.onReply,
    required this.onDelete,
  });

  final EchoComment comment;
  final String userName;
  final String userAvatarPath;
  final String characterName;
  final String characterAvatarPath;
  final bool isAuthor;
  final int likeCount;
  final bool isReplying;
  final bool canGenerateReply;
  final VoidCallback onGenerateReply;
  final VoidCallback onLike;
  final VoidCallback onReply;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isCharacter = comment.authorType == EchoCommentAuthorType.character;
    final isWorld = comment.authorType == EchoCommentAuthorType.world;
    final savedName = comment.authorNameSnapshot.trim();
    final name = isWorld
        ? (savedName.isEmpty ? '世界居民' : savedName)
        : isCharacter
        ? (savedName.isNotEmpty
              ? savedName
              : (characterName.isEmpty ? '角色' : characterName))
        : userName;
    final savedAvatar = comment.authorAvatarSnapshot.trim();
    final avatarPath = isWorld
        ? savedAvatar
        : isCharacter
        ? (savedAvatar.isNotEmpty ? savedAvatar : characterAvatarPath.trim())
        : userAvatarPath.trim();

    return Container(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(5, 9, 2, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        border: const Border(
          bottom: BorderSide(color: Color(0x35FFFFFF), width: 0.7),
        ),
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
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isAuthor
                                    ? const Color(0xFFC96F86)
                                    : const Color(0xFF576B95),
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (isCharacter) ...[
                            const SizedBox(width: 6),
                            const AiVerifiedBadge(size: 13),
                          ],
                          if (isAuthor) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0x66FFF0F4),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: const Text(
                                '作者',
                                style: TextStyle(
                                  color: Color(0xFFC96F86),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
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
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      _detailTime(comment.createdAt),
                      style: const TextStyle(
                        color: Color(0xFFA0A8AD),
                        fontSize: 10.5,
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: onReply,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(36, 28),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('回复'),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: onLike,
                      icon: Icon(
                        likeCount > 0
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 16,
                      ),
                      label: Text('$likeCount'),
                      style: TextButton.styleFrom(
                        foregroundColor: likeCount > 0
                            ? const Color(0xFFE4869C)
                            : const Color(0xFF929CA2),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
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
                errorBuilder: (_, _, _) => Text(
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
          border: Border(top: BorderSide(color: Color(0xFFE5E5E5))),
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
                IconButton(
                  tooltip: '表情（敬请期待）',
                  onPressed: () => ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('表情功能敬请期待'))),
                  icon: const Icon(Icons.sentiment_satisfied_alt_outlined),
                  color: const Color(0xFF7C8D96),
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 500,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: '说点什么吧…',
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
                FilledButton(
                  onPressed: saving ? null : onSubmit,
                  child: saving
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('发送'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _detailTime(DateTime time) {
  final now = DateTime.now();
  final difference = now.difference(time);
  if (difference.inMinutes < 1) return '刚刚';
  if (difference.inHours < 1) return '${difference.inMinutes}分钟前';
  if (difference.inDays < 1) return '${difference.inHours}小时前';
  if (difference.inDays == 1) return '昨天';
  return '${time.month}月${time.day}日';
}
