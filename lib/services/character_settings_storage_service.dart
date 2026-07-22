import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/character_settings.dart';

class CharacterSettingsStorageService {
  Future<File> _settingsFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/character_settings.json');
  }

  Future<CharacterSettings> loadSettings() async {
    final file = await _settingsFile();
    if (!await file.exists()) {
      final defaults = CharacterSettings.defaults();
      await saveSettings(defaults);
      return defaults;
    }

    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return CharacterSettings.defaults();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return CharacterSettings.defaults();
      return CharacterSettings.fromJson(decoded);
    } catch (_) {
      return CharacterSettings.defaults();
    }
  }

  Future<void> saveSettings(CharacterSettings settings) async {
    final file = await _settingsFile();
    await file.writeAsString(jsonEncode(settings.toJson()), flush: true);
  }

  Future<void> restoreDefaults() async {
    await saveSettings(CharacterSettings.defaults());
  }
}
