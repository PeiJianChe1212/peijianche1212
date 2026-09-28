import 'package:flutter/material.dart';

import '../theme/peilink_theme_scope.dart';

class EchoInteractionBar extends StatelessWidget {
  const EchoInteractionBar({
    super.key,
    required this.likeCount,
    required this.commentCount,
    required this.collectCount,
    required this.viewCount,
    required this.isLiked,
    required this.isCollected,
    required this.onLike,
    required this.onComment,
    required this.onCollect,
  });

  final int likeCount;
  final int commentCount;
  final int collectCount;
  final int viewCount;
  final bool isLiked;
  final bool isCollected;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onCollect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: Row(
        children: [
          _Action(
            icon: isLiked
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            count: likeCount,
            active: isLiked,
            onTap: onLike,
            semanticLabel: '点赞 $likeCount',
          ),
          _Action(
            icon: Icons.chat_bubble_outline_rounded,
            count: commentCount,
            onTap: onComment,
            semanticLabel: '评论 $commentCount',
          ),
          _Action(
            icon: isCollected ? Icons.star_rounded : Icons.star_border_rounded,
            count: collectCount,
            active: isCollected,
            onTap: onCollect,
            semanticLabel: '${isCollected ? '已收藏' : '收藏'} $collectCount',
          ),
          _Action(
            icon: Icons.visibility_outlined,
            count: viewCount,
            semanticLabel: '浏览 $viewCount',
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.count,
    required this.semanticLabel,
    this.active = false,
    this.onTap,
  });
  final IconData icon;
  final int count;
  final String semanticLabel;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final echoTheme = PeiLinkThemeScope.of(context).publicEchoTheme;
    final color = active
        ? echoTheme.selectedActionColor
        : echoTheme.actionColor;
    return Expanded(
      child: Semantics(
        label: semanticLabel,
        button: onTap != null,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  '$count',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
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
