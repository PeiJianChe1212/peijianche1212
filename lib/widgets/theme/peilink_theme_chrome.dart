import 'package:flutter/material.dart';

import '../../theme/peilink_theme_config.dart';
import '../../theme/theme_background_surface.dart';
import '../../theme/theme_background.dart';
import 'peilink_theme_scope.dart';

class PeiLinkThemeTopBar extends StatelessWidget
    implements PreferredSizeWidget {
  const PeiLinkThemeTopBar({
    super.key,
    required this.title,
    this.leading,
    this.subtitle,
    this.avatar,
    this.actions = const [],
    this.theme,
  });
  final Widget title;
  final Widget? leading;
  final Widget? subtitle;
  final Widget? avatar;
  final List<Widget> actions;
  final PeiLinkTopBarTheme? theme;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final value = theme ?? PeiLinkThemeScope.of(context).topBarTheme;
    return AppBar(
      leading: leading,
      backgroundColor: value.background,
      foregroundColor: value.foreground,
      elevation: value.elevation,
      surfaceTintColor: Colors.transparent,
      title: Row(
        children: avatar == null
            ? [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [title, ?subtitle],
                  ),
                ),
              ]
            : [
                avatar!,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [title, ?subtitle],
                  ),
                ),
              ],
      ),
      actions: actions,
    );
  }
}

class PeiLinkThemeChatComposer extends StatelessWidget {
  const PeiLinkThemeChatComposer({super.key, required this.child, this.theme});
  final Widget child;
  final PeiLinkBottomBarTheme? theme;
  @override
  Widget build(BuildContext context) {
    final value = theme ?? PeiLinkThemeScope.of(context).bottomBarTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: value.background,
        border: Border(top: BorderSide(color: value.border)),
      ),
      child: child,
    );
  }
}

enum PeiLinkThemeIcon { voice, image, more }

class PeiLinkThemeIconButton extends StatelessWidget {
  const PeiLinkThemeIconButton({
    super.key,
    required this.type,
    required this.onPressed,
    this.icon,
    this.tooltip,
  });
  final PeiLinkThemeIcon type;
  final VoidCallback? onPressed;
  final Widget? icon;
  final String? tooltip;
  @override
  Widget build(BuildContext context) {
    final theme = PeiLinkThemeScope.of(context).iconTheme;
    final fallback = switch (type) {
      PeiLinkThemeIcon.voice => Icons.mic_none_rounded,
      PeiLinkThemeIcon.image => Icons.image_outlined,
      PeiLinkThemeIcon.more => Icons.add_circle_outline_rounded,
    };
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      color: theme.foreground,
      style: IconButton.styleFrom(backgroundColor: theme.background),
      icon: icon ?? Icon(fallback, size: theme.size),
    );
  }
}

class PeiLinkThemeScaffold extends StatelessWidget {
  const PeiLinkThemeScaffold({
    super.key,
    required this.body,
    this.background,
    this.decoration,
  });
  final Widget body;
  final ThemeBackground? background;
  final PeiLinkDecorationTheme? decoration;
  @override
  Widget build(BuildContext context) {
    final config = PeiLinkThemeScope.of(context);
    final decorations = decoration ?? config.decorationTheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        ThemeBackgroundSurface(background: background ?? config.chatBackground),
        body,
        IgnorePointer(
          key: const ValueKey('peilink-theme-decoration-layer'),
          child: Stack(
            children: [
              if (decorations.top != null)
                Align(
                  alignment: Alignment.topCenter,
                  child: DecoratedBox(
                    decoration: decorations.top!,
                    child: const SizedBox(width: double.infinity, height: 120),
                  ),
                ),
              if (decorations.bottom != null)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: DecoratedBox(
                    decoration: decorations.bottom!,
                    child: const SizedBox(width: double.infinity, height: 120),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
