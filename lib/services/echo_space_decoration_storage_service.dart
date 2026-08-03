import 'dart:convert';
import 'dart:io';

import 'character_scope_service.dart';

enum EchoSpaceThemeMode { airy, balanced, immersive }

class EchoSpaceDecorationConfig {
  const EchoSpaceDecorationConfig({
    this.background = '',
    this.themeMode = EchoSpaceThemeMode.balanced,
  });

  final String background;
  final EchoSpaceThemeMode themeMode;

  EchoSpaceDecorationConfig copyWith({
    String? background,
    EchoSpaceThemeMode? themeMode,
  }) {
    return EchoSpaceDecorationConfig(
      background: background ?? this.background,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  Map<String, dynamic> toJson() => {
    'background': background,
    'themeMode': themeMode.name,
  };

  factory EchoSpaceDecorationConfig.fromJson(Map<dynamic, dynamic> json) {
    final modeName = json['themeMode']?.toString() ?? '';
    return EchoSpaceDecorationConfig(
      background: json['background']?.toString() ?? '',
      themeMode: EchoSpaceThemeMode.values.firstWhere(
        (mode) => mode.name == modeName,
        orElse: () => EchoSpaceThemeMode.balanced,
      ),
    );
  }
}

class EchoSpaceDecorationStorageService {
  const EchoSpaceDecorationStorageService({required this.characterId});

  final String characterId;

  Future<File> _file() =>
      CharacterScopeService(characterId).dataFile('echo_space_decoration.json');

  Future<EchoSpaceDecorationConfig> load() async {
    final file = await _file();
    if (!await file.exists()) return const EchoSpaceDecorationConfig();
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        return EchoSpaceDecorationConfig.fromJson(decoded);
      }
    } catch (_) {}
    return const EchoSpaceDecorationConfig();
  }

  Future<void> save(EchoSpaceDecorationConfig config) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(config.toJson()), flush: true);
  }
}
