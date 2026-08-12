import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import '../config/peilink_runtime.dart';

import '../theme/app_theme_background.dart';
import '../theme/chat_visual_theme.dart';
import '../theme/theme_background.dart';

class PeiLinkAppearanceController extends ChangeNotifier {
  PeiLinkAppearanceController._({this._fileProvider});

  factory PeiLinkAppearanceController.testing({
    required Future<File> Function() fileProvider,
  }) => PeiLinkAppearanceController._(fileProvider: fileProvider);

  static final instance = PeiLinkAppearanceController._();
  final Future<File> Function()? _fileProvider;

  ThemeBackground _background = AppThemeBackground.current;
  ChatBubbleTheme _bubbleTheme = ChatVisualThemeCatalog.qqRounded;
  ChatFontTheme _fontTheme = ChatVisualThemeCatalog.systemFont;

  ThemeBackground get background => _background;
  ChatBubbleTheme get bubbleTheme => _bubbleTheme;
  ChatFontTheme get fontTheme => _fontTheme;

  Future<File> _file() async {
    if (_fileProvider != null) return _fileProvider();
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/peilink_appearance.json');
  }

  Future<void> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;
      _background = _backgroundById(decoded['backgroundId']?.toString());
      _bubbleTheme = _bubbleById(decoded['bubbleThemeId']?.toString());
      _fontTheme = _fontById(decoded['fontThemeId']?.toString());
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setBackground(ThemeBackground value) async {
    _background = value;
    notifyListeners();
    await _save();
  }

  Future<void> setBubbleTheme(ChatBubbleTheme value) async {
    _bubbleTheme = value;
    notifyListeners();
    await _save();
  }

  Future<void> setFontTheme(ChatFontTheme value) async {
    _fontTheme = value;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      final file = await _file();
      await file.writeAsString(
        jsonEncode({
          'backgroundId': _background.id,
          'bubbleThemeId': _bubbleTheme.id,
          'fontThemeId': _fontTheme.id,
        }),
        flush: true,
      );
    } catch (_) {}
  }

  ThemeBackground _backgroundById(String? id) {
    return [
          ...AppThemeBackground.builtInPack,
          ...AppThemeBackground.legacyAtmospherePack,
        ].where((item) => item.id == id).firstOrNull ??
        AppThemeBackground.current;
  }

  ChatBubbleTheme _bubbleById(String? id) =>
      ChatVisualThemeCatalog.bubbleThemes
          .where((item) => item.id == id)
          .firstOrNull ??
      ChatVisualThemeCatalog.qqRounded;

  ChatFontTheme _fontById(String? id) =>
      ChatVisualThemeCatalog.fontThemes
          .where((item) => item.id == id)
          .firstOrNull ??
      ChatVisualThemeCatalog.systemFont;
}

class PeiLinkAppearanceScope
    extends InheritedNotifier<PeiLinkAppearanceController> {
  const PeiLinkAppearanceScope({
    super.key,
    required PeiLinkAppearanceController controller,
    required super.child,
  }) : super(notifier: controller);

  static PeiLinkAppearanceController of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<PeiLinkAppearanceScope>()
            ?.notifier ??
        PeiLinkAppearanceController.instance;
  }
}
