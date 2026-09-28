import 'package:flutter/material.dart';

import '../../services/peilink_theme_service.dart';
import '../../theme/peilink_theme_config.dart';

class PeiLinkThemeScope extends InheritedNotifier<PeiLinkThemeController> {
  const PeiLinkThemeScope({
    super.key,
    required PeiLinkThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  static PeiLinkThemeController controllerOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<PeiLinkThemeScope>()
          ?.notifier ??
      PeiLinkThemeController.instance;

  static PeiLinkThemeConfig of(BuildContext context) =>
      controllerOf(context).chatTheme;
}

class CharacterEchoThemeScope extends InheritedWidget {
  const CharacterEchoThemeScope({
    super.key,
    required this.characterId,
    required this.theme,
    required super.child,
  });
  final String characterId;
  final CharacterEchoThemeConfig theme;

  static CharacterEchoThemeConfig of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<CharacterEchoThemeScope>()
          ?.theme ??
      PeiLinkThemeDefaults.privateEcho;

  @override
  bool updateShouldNotify(CharacterEchoThemeScope oldWidget) =>
      oldWidget.characterId != characterId || oldWidget.theme.id != theme.id;
}
