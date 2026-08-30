import 'package:flutter/material.dart';

import 'peilink_tokens.dart';

enum PeiLinkAppBarMode { transparent, glass }

class PeiLinkAppBar extends StatelessWidget implements PreferredSizeWidget {
  const PeiLinkAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.mode = PeiLinkAppBarMode.transparent,
  });

  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final PeiLinkAppBarMode mode;

  static Widget addAction({
    required VoidCallback onPressed,
    String tooltip = '添加',
  }) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: const Icon(Icons.add_rounded),
  );

  static Widget moreAction({
    required VoidCallback onPressed,
    String tooltip = '更多',
  }) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: const Icon(Icons.more_horiz_rounded),
  );

  @override
  Size get preferredSize => Size.fromHeight(subtitle == null ? 58 : 70);

  @override
  Widget build(BuildContext context) => AppBar(
    automaticallyImplyLeading: automaticallyImplyLeading,
    leading: leading,
    titleSpacing: 4,
    centerTitle: false,
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (subtitle != null)
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PeiLinkTypography.pageSubtitle,
          ),
      ],
    ),
    titleTextStyle: PeiLinkTypography.pageTitle,
    foregroundColor: PeiLinkColors.textPrimary,
    backgroundColor: mode == PeiLinkAppBarMode.glass
        ? Colors.white.withValues(alpha: 0.5)
        : Colors.transparent,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    actions: actions,
  );
}
