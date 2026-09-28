import 'package:flutter/material.dart';

import 'app_theme_background.dart';
import 'chat_visual_theme.dart';
import 'theme_background.dart';

@immutable
class PeiLinkTopBarTheme {
  const PeiLinkTopBarTheme({
    this.background = Colors.transparent,
    this.foreground = const Color(0xFF1B2028),
    this.elevation = 0,
  });
  final Color background;
  final Color foreground;
  final double elevation;
}

@immutable
class PeiLinkBottomBarTheme {
  const PeiLinkBottomBarTheme({
    this.background = Colors.transparent,
    this.border = Colors.transparent,
    this.radius = 22,
    this.padding = const EdgeInsets.fromLTRB(10, 3, 10, 5),
  });
  final Color background;
  final Color border;
  final double radius;
  final EdgeInsets padding;
}

@immutable
class PeiLinkIconTheme {
  const PeiLinkIconTheme({
    this.foreground = const Color(0xFF6975CF),
    this.background = Colors.transparent,
    this.size = 27,
  });
  final Color foreground;
  final Color background;
  final double size;
}

@immutable
class PeiLinkNavigationTheme {
  const PeiLinkNavigationTheme({
    this.background = const Color(0xC2FFFFFF),
    this.border = const Color(0xB8FFFFFF),
    this.selectedBackground = const Color(0xDBDDE8FA),
    this.selected = const Color(0xFF526DA5),
    this.unselected = const Color(0xFF66737B),
    this.shadow = const Color(0x29152D3D),
    this.selectedLabelStyle = const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
    ),
    this.unselectedLabelStyle = const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w500,
    ),
    this.iconAssetDirectory,
    this.decoration,
  });
  final Color background;
  final Color border;
  final Color selectedBackground;
  final Color selected;
  final Color unselected;
  final Color shadow;
  final TextStyle selectedLabelStyle;
  final TextStyle unselectedLabelStyle;
  final String? iconAssetDirectory;
  final Decoration? decoration;
}

@immutable
class PeiLinkDecorationTheme {
  const PeiLinkDecorationTheme({this.top, this.bottom, this.floating});
  final Decoration? top;
  final Decoration? bottom;
  final Decoration? floating;
}

enum PeiLinkAvatarShape { roundedSquare }

@immutable
class AvatarFrameSpec {
  const AvatarFrameSpec({
    required this.id,
    this.assetPath,
    this.border,
    this.paddingRatio = .08,
    this.shape = PeiLinkAvatarShape.roundedSquare,
    this.borderRadiusRatio = .18,
  });
  final String id;
  final String? assetPath;
  final Border? border;
  final double paddingRatio;
  final PeiLinkAvatarShape shape;
  final double borderRadiusRatio;
}

@immutable
class AvatarFrameTheme {
  const AvatarFrameTheme({
    this.user,
    this.character,
    this.group,
    this.avatarShape = PeiLinkAvatarShape.roundedSquare,
    this.avatarBorderRadiusRatio = .18,
  });
  final AvatarFrameSpec? user;
  final AvatarFrameSpec? character;
  final AvatarFrameSpec? group;
  final PeiLinkAvatarShape avatarShape;
  final double avatarBorderRadiusRatio;
}

@immutable
class PublicEchoThemeConfig {
  const PublicEchoThemeConfig({
    required this.background,
    required this.topBarTheme,
    this.cardColor = const Color(0xE8FFFFFF),
    this.actionColor = const Color(0xFF849198),
    this.selectedActionColor = const Color(0xFFE4869C),
    this.decorationTheme = const PeiLinkDecorationTheme(),
  });
  final ThemeBackground background;
  final PeiLinkTopBarTheme topBarTheme;
  final Color cardColor;
  final Color actionColor;
  final Color selectedActionColor;
  final PeiLinkDecorationTheme decorationTheme;
}

@immutable
class PeiLinkThemeConfig {
  const PeiLinkThemeConfig({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.chatBackground,
    required this.groupBackground,
    required this.topBarTheme,
    required this.groupTopBarTheme,
    required this.bottomBarTheme,
    required this.iconTheme,
    this.navigationTheme = const PeiLinkNavigationTheme(),
    required this.defaultBubbleThemeId,
    required this.publicEchoTheme,
    this.decorationTheme = const PeiLinkDecorationTheme(),
    this.avatarFrameTheme = const AvatarFrameTheme(),
  });
  final String id;
  final String name;
  final String subtitle;
  final ThemeBackground chatBackground;
  final ThemeBackground groupBackground;
  final PeiLinkTopBarTheme topBarTheme;
  final PeiLinkTopBarTheme groupTopBarTheme;
  final PeiLinkBottomBarTheme bottomBarTheme;
  final PeiLinkIconTheme iconTheme;
  final PeiLinkNavigationTheme navigationTheme;
  final String defaultBubbleThemeId;
  final PeiLinkDecorationTheme decorationTheme;
  final AvatarFrameTheme avatarFrameTheme;
  final PublicEchoThemeConfig publicEchoTheme;

  ChatBubbleTheme get defaultBubbleTheme =>
      ChatVisualThemeCatalog.bubbleThemes
          .where((item) => item.id == defaultBubbleThemeId)
          .firstOrNull ??
      ChatVisualThemeCatalog.qqRounded;

  PeiLinkThemeConfig copyWithComponents({
    ThemeBackground? chatBackground,
    ThemeBackground? groupBackground,
    AvatarFrameTheme? avatarFrameTheme,
    PeiLinkNavigationTheme? navigationTheme,
    String? defaultBubbleThemeId,
  }) => PeiLinkThemeConfig(
    id: id,
    name: name,
    subtitle: subtitle,
    chatBackground: chatBackground ?? this.chatBackground,
    groupBackground: groupBackground ?? this.groupBackground,
    topBarTheme: topBarTheme,
    groupTopBarTheme: groupTopBarTheme,
    bottomBarTheme: bottomBarTheme,
    iconTheme: iconTheme,
    navigationTheme: navigationTheme ?? this.navigationTheme,
    defaultBubbleThemeId: defaultBubbleThemeId ?? this.defaultBubbleThemeId,
    decorationTheme: decorationTheme,
    avatarFrameTheme: avatarFrameTheme ?? this.avatarFrameTheme,
    publicEchoTheme: PublicEchoThemeConfig(
      background: chatBackground ?? publicEchoTheme.background,
      topBarTheme: publicEchoTheme.topBarTheme,
      cardColor: publicEchoTheme.cardColor,
      actionColor: publicEchoTheme.actionColor,
      selectedActionColor: publicEchoTheme.selectedActionColor,
      decorationTheme: publicEchoTheme.decorationTheme,
    ),
  );
}

@immutable
class CharacterEchoThemeConfig {
  const CharacterEchoThemeConfig({
    required this.id,
    required this.background,
    required this.topBarTheme,
    this.cardColor = const Color(0xADFFFFFF),
    this.iconTheme = const PeiLinkIconTheme(),
    this.decorationTheme = const PeiLinkDecorationTheme(),
    this.avatarFrameTheme,
  });
  final String id;
  final ThemeBackground background;
  final PeiLinkTopBarTheme topBarTheme;
  final Color cardColor;
  final PeiLinkIconTheme iconTheme;
  final PeiLinkDecorationTheme decorationTheme;
  final AvatarFrameSpec? avatarFrameTheme;
}

abstract final class PeiLinkThemeDefaults {
  static final PeiLinkThemeConfig chat = PeiLinkThemeConfig(
    id: 'default',
    name: '默认主题',
    subtitle: 'PeiLink 原生外观',
    chatBackground: AppThemeBackground.current,
    groupBackground: AppThemeBackground.current,
    topBarTheme: const PeiLinkTopBarTheme(),
    groupTopBarTheme: const PeiLinkTopBarTheme(background: Color(0xF0FFFFFF)),
    bottomBarTheme: const PeiLinkBottomBarTheme(),
    iconTheme: const PeiLinkIconTheme(),
    defaultBubbleThemeId: ChatVisualThemeCatalog.qqRounded.id,
    publicEchoTheme: PublicEchoThemeConfig(
      background: AppThemeBackground.current,
      topBarTheme: const PeiLinkTopBarTheme(),
    ),
  );

  static const ThemeBackground butterflyFoxBackground = ThemeBackground(
    id: 'butterfly_fox_background',
    name: '蝶梦白狐',
    imagePath: 'assets/themes/butterfly_fox/backgrounds/chat.png',
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFF1F6FF), Color(0xFFE8F0FF), Color(0xFFF9FBFF)],
    ),
    opacity: .42,
  );

  static final PeiLinkThemeConfig butterflyFox = PeiLinkThemeConfig(
    id: 'butterfly_fox',
    name: '蝶梦白狐',
    subtitle: '蓝蝶 · 白狐 · 月夜',
    chatBackground: butterflyFoxBackground,
    groupBackground: butterflyFoxBackground,
    topBarTheme: const PeiLinkTopBarTheme(
      background: Color(0xE8EDF5FF),
      foreground: Color(0xFF36558D),
      elevation: 0,
    ),
    groupTopBarTheme: const PeiLinkTopBarTheme(
      background: Color(0xE8EDF5FF),
      foreground: Color(0xFF36558D),
    ),
    bottomBarTheme: const PeiLinkBottomBarTheme(
      background: Color(0x66EDF5FF),
      border: Color(0x996F91D1),
      radius: 24,
    ),
    iconTheme: const PeiLinkIconTheme(
      foreground: Color(0xFF496CAA),
      background: Color(0x35FFFFFF),
    ),
    navigationTheme: const PeiLinkNavigationTheme(
      background: Color(0xC9DDE9FC),
      border: Color(0xE8FFFFFF),
      selectedBackground: Color(0xB8F4F8FF),
      selected: Color(0xFF365FA7),
      unselected: Color(0xFF6D82A5),
      shadow: Color(0x33476EA7),
      selectedLabelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: .2,
      ),
      unselectedLabelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
      iconAssetDirectory: 'assets/themes/butterfly_fox/icons/navigation',
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xDDF4F8FF), Color(0xC8D7E7FF)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    ),
    defaultBubbleThemeId: ChatVisualThemeCatalog.minimal.id,
    decorationTheme: const PeiLinkDecorationTheme(
      top: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0x264A79C5), Color(0x00FFFFFF)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    ),
    avatarFrameTheme: const AvatarFrameTheme(
      user: AvatarFrameSpec(
        id: 'butterfly_fox_user',
        assetPath: 'assets/themes/butterfly_fox/frames/avatar.png',
        paddingRatio: .055,
      ),
      character: AvatarFrameSpec(
        id: 'butterfly_fox_character',
        assetPath: 'assets/themes/butterfly_fox/frames/avatar.png',
        paddingRatio: .055,
      ),
      group: AvatarFrameSpec(
        id: 'butterfly_fox_group',
        border: Border.fromBorderSide(
          BorderSide(color: Color(0xFF89A8DE), width: 1.2),
        ),
        paddingRatio: .025,
      ),
    ),
    publicEchoTheme: const PublicEchoThemeConfig(
      background: butterflyFoxBackground,
      topBarTheme: PeiLinkTopBarTheme(
        background: Color(0xE8EDF5FF),
        foreground: Color(0xFF36558D),
      ),
      cardColor: Color(0xD9F7FAFF),
      actionColor: Color(0xFF5278B8),
      selectedActionColor: Color(0xFF315FA8),
    ),
  );

  static final CharacterEchoThemeConfig privateEcho = CharacterEchoThemeConfig(
    id: 'default_private_echo',
    background: AppThemeBackground.current,
    topBarTheme: const PeiLinkTopBarTheme(),
  );
}
