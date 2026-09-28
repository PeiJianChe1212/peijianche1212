import 'peilink_theme_config.dart';
import 'chat_visual_theme.dart';
import 'theme_background.dart';

class BackgroundRegistry {
  BackgroundRegistry(Iterable<PeiLinkThemeConfig> presets)
    : _values = {for (final item in presets) item.id: item.chatBackground};
  final Map<String, ThemeBackground> _values;
  List<String> get ids => List.unmodifiable(_values.keys);
  ThemeBackground? resolve(String? id) => id == null ? null : _values[id];
}

class AvatarFrameRegistry {
  AvatarFrameRegistry(Iterable<PeiLinkThemeConfig> presets)
    : _values = {for (final item in presets) item.id: item.avatarFrameTheme};
  final Map<String, AvatarFrameTheme> _values;
  List<String> get ids => List.unmodifiable(_values.keys);
  AvatarFrameTheme? resolve(String? id) => id == null ? null : _values[id];
}

class BottomNavigationRegistry {
  BottomNavigationRegistry(Iterable<PeiLinkThemeConfig> presets)
    : _values = {for (final item in presets) item.id: item.navigationTheme};
  final Map<String, PeiLinkNavigationTheme> _values;
  List<String> get ids => List.unmodifiable(_values.keys);
  PeiLinkNavigationTheme? resolve(String? id) =>
      id == null ? null : _values[id];
}

class PeiLinkThemeRegistry {
  PeiLinkThemeRegistry({
    Iterable<PeiLinkThemeConfig> chatThemes = const [],
    Iterable<CharacterEchoThemeConfig> privateEchoThemes = const [],
  }) : _chatThemes = {
         PeiLinkThemeDefaults.chat.id: PeiLinkThemeDefaults.chat,
         PeiLinkThemeDefaults.butterflyFox.id:
             PeiLinkThemeDefaults.butterflyFox,
         for (final theme in chatThemes) theme.id: theme,
       },
       _privateEchoThemes = {
         PeiLinkThemeDefaults.privateEcho.id: PeiLinkThemeDefaults.privateEcho,
         for (final theme in privateEchoThemes) theme.id: theme,
       } {
    backgroundRegistry = BackgroundRegistry(_chatThemes.values);
    avatarFrameRegistry = AvatarFrameRegistry(_chatThemes.values);
    bottomNavigationRegistry = BottomNavigationRegistry(_chatThemes.values);
  }

  static final PeiLinkThemeRegistry instance = PeiLinkThemeRegistry();
  final Map<String, PeiLinkThemeConfig> _chatThemes;
  final Map<String, CharacterEchoThemeConfig> _privateEchoThemes;
  late final BackgroundRegistry backgroundRegistry;
  late final AvatarFrameRegistry avatarFrameRegistry;
  late final BottomNavigationRegistry bottomNavigationRegistry;

  List<PeiLinkThemeConfig> get chatThemes =>
      List.unmodifiable(_chatThemes.values);

  PeiLinkThemeConfig chat(String? id) =>
      _chatThemes[id] ?? PeiLinkThemeDefaults.chat;

  PeiLinkThemeConfig effective({
    required String presetId,
    String? backgroundOverrideId,
    String? avatarFrameOverrideId,
    String? bubbleOverrideId,
    String? bottomNavigationOverrideId,
  }) {
    final preset = chat(presetId);
    final bubble = ChatVisualThemeCatalog.bubbleThemes
        .where((item) => item.id == bubbleOverrideId)
        .firstOrNull;
    return preset.copyWithComponents(
      chatBackground: backgroundRegistry.resolve(backgroundOverrideId),
      groupBackground: backgroundRegistry.resolve(backgroundOverrideId),
      avatarFrameTheme: avatarFrameRegistry.resolve(avatarFrameOverrideId),
      navigationTheme: bottomNavigationRegistry.resolve(
        bottomNavigationOverrideId,
      ),
      defaultBubbleThemeId: bubble?.id,
    );
  }

  CharacterEchoThemeConfig privateEcho(String? id) =>
      _privateEchoThemes[id] ?? PeiLinkThemeDefaults.privateEcho;
}
