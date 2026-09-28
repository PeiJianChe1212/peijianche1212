import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../config/peilink_runtime.dart';
import '../platform/storage/platform_storage.dart';
import '../theme/peilink_theme_config.dart';
import '../theme/peilink_theme_registry.dart';

class PeiLinkThemeController extends ChangeNotifier {
  PeiLinkThemeController({this.storage, PeiLinkThemeRegistry? registry})
    : registry = registry ?? PeiLinkThemeRegistry.instance;

  static final instance = PeiLinkThemeController();
  static const _fileName = 'theme_selections.json';
  final PlatformStorage? storage;
  final PeiLinkThemeRegistry registry;
  String _chatThemeId = 'default';
  String? _backgroundOverrideId;
  String? _avatarFrameOverrideId;
  String? _bubbleOverrideId;
  String? _bottomNavigationOverrideId;
  Map<String, String> _privateEchoThemeIds = const {};

  String get selectedChatThemeId => _chatThemeId;
  String get selectedThemePresetId => _chatThemeId;
  String? get backgroundOverrideId => _backgroundOverrideId;
  String? get avatarFrameOverrideId => _avatarFrameOverrideId;
  String? get bubbleOverrideId => _bubbleOverrideId;
  String? get bottomNavigationOverrideId => _bottomNavigationOverrideId;
  PeiLinkThemeConfig get chatTheme => registry.effective(
    presetId: _chatThemeId,
    backgroundOverrideId: _backgroundOverrideId,
    avatarFrameOverrideId: _avatarFrameOverrideId,
    bubbleOverrideId: _bubbleOverrideId,
    bottomNavigationOverrideId: _bottomNavigationOverrideId,
  );
  PeiLinkThemeConfig get presetTheme => registry.chat(_chatThemeId);
  CharacterEchoThemeConfig privateEchoTheme(String characterId) =>
      registry.privateEcho(_privateEchoThemeIds[characterId]);

  Future<PlatformStorage> _platformStorage() =>
      storage == null ? PeiLinkRuntime.storage() : Future.value(storage);

  Future<void> load() async {
    try {
      final storage = await _platformStorage();
      if (!await storage.exists(_fileName)) return;
      final decoded = jsonDecode(await storage.readText(_fileName));
      if (decoded is! Map) return;
      _chatThemeId = registry
          .chat(
            (decoded['selectedThemePresetId'] ?? decoded['selectedChatThemeId'])
                ?.toString(),
          )
          .id;
      _backgroundOverrideId = _validComponentId(
        decoded['backgroundOverrideId'],
        registry.backgroundRegistry.ids,
      );
      _avatarFrameOverrideId = _validComponentId(
        decoded['avatarFrameOverrideId'],
        registry.avatarFrameRegistry.ids,
      );
      _bubbleOverrideId = decoded['bubbleOverrideId']?.toString();
      _bottomNavigationOverrideId = _validComponentId(
        decoded['bottomNavigationOverrideId'],
        registry.bottomNavigationRegistry.ids,
      );
      final rawPrivate = decoded['characterPrivateEchoThemeIds'];
      _privateEchoThemeIds = rawPrivate is Map
          ? rawPrivate.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : const {};
      notifyListeners();
    } catch (_) {}
  }

  Future<void> selectChatTheme(String id) async {
    await applyFullTheme(id);
  }

  Future<void> applyFullTheme(String id) async {
    _chatThemeId = registry.chat(id).id;
    _backgroundOverrideId = null;
    _avatarFrameOverrideId = null;
    _bubbleOverrideId = null;
    _bottomNavigationOverrideId = null;
    notifyListeners();
    await _save();
  }

  Future<void> setBackgroundOverride(String? id) =>
      _setOverride(id, registry.backgroundRegistry.ids, (value) {
        _backgroundOverrideId = value;
      });

  Future<void> setAvatarFrameOverride(String? id) =>
      _setOverride(id, registry.avatarFrameRegistry.ids, (value) {
        _avatarFrameOverrideId = value;
      });

  Future<void> setBubbleOverride(String? id) async {
    _bubbleOverrideId = id?.trim().isEmpty == true ? null : id;
    notifyListeners();
    await _save();
  }

  Future<void> setBottomNavigationOverride(String? id) =>
      _setOverride(id, registry.bottomNavigationRegistry.ids, (value) {
        _bottomNavigationOverrideId = value;
      });

  Future<void> _setOverride(
    String? id,
    List<String> validIds,
    void Function(String?) assign,
  ) async {
    assign(_validComponentId(id, validIds));
    notifyListeners();
    await _save();
  }

  static String? _validComponentId(Object? raw, List<String> validIds) {
    final id = raw?.toString().trim();
    if (id == null || id.isEmpty || !validIds.contains(id)) return null;
    return id;
  }

  Future<void> setPrivateEchoTheme(String characterId, String id) async {
    _privateEchoThemeIds = {
      ..._privateEchoThemeIds,
      characterId: registry.privateEcho(id).id,
    };
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    final storage = await _platformStorage();
    await storage.replaceTextSafely(
      _fileName,
      jsonEncode({
        'selectedChatThemeId': _chatThemeId,
        'selectedThemePresetId': _chatThemeId,
        'backgroundOverrideId': _backgroundOverrideId,
        'avatarFrameOverrideId': _avatarFrameOverrideId,
        'bubbleOverrideId': _bubbleOverrideId,
        'bottomNavigationOverrideId': _bottomNavigationOverrideId,
        'characterPrivateEchoThemeIds': _privateEchoThemeIds,
      }),
    );
  }
}
