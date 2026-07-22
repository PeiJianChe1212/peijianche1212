import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class ChatSettings {
  const ChatSettings({
    this.openingMessage = '回来了？今天过得怎么样。',
    this.conversationMode = 'basic',
    this.temperature = 0.72,
    this.replyLength = 'standard',
    this.initiative = 0.58,
    this.intimacy = 0.52,
    this.tsundere = 0.62,
    this.proactiveEnabled = true,
    this.lateNightMessages = true,
    this.maxProactivePerDay = 2,
  });

  final String openingMessage;
  final String conversationMode;
  final double temperature;
  final String replyLength;
  final double initiative;
  final double intimacy;
  final double tsundere;
  final bool proactiveEnabled;
  final bool lateNightMessages;
  final int maxProactivePerDay;

  Map<String, dynamic> toJson() => {
    'openingMessage': openingMessage,
    'conversationMode': conversationMode,
    'temperature': temperature,
    'replyLength': replyLength,
    'initiative': initiative,
    'intimacy': intimacy,
    'tsundere': tsundere,
    'proactiveEnabled': proactiveEnabled,
    'lateNightMessages': lateNightMessages,
    'maxProactivePerDay': maxProactivePerDay,
  };

  factory ChatSettings.fromJson(Map<dynamic, dynamic> json) {
    final mode = json['conversationMode']?.toString();
    final length = json['replyLength']?.toString();
    final opening = json['openingMessage']?.toString().trim();

    double readDouble(String key, double fallback, double min, double max) {
      final value = json[key];
      return value is num
          ? value.toDouble().clamp(min, max).toDouble()
          : fallback;
    }

    int readInt(String key, int fallback, int min, int max) {
      final value = json[key];
      return value is num ? value.toInt().clamp(min, max).toInt() : fallback;
    }

    return ChatSettings(
      openingMessage: opening == null || opening.isEmpty
          ? '回来了？今天过得怎么样。'
          : opening,
      conversationMode:
          const {'basic', 'heart', 'delicate', 'long', 'deep'}.contains(mode)
          ? mode!
          : 'basic',
      temperature: readDouble('temperature', 0.72, 0.55, 0.90),
      replyLength: const {'short', 'standard', 'long'}.contains(length)
          ? length!
          : 'standard',
      initiative: readDouble('initiative', 0.58, 0, 1),
      intimacy: readDouble('intimacy', 0.52, 0, 1),
      tsundere: readDouble('tsundere', 0.62, 0, 1),
      proactiveEnabled: json['proactiveEnabled'] != false,
      lateNightMessages: json['lateNightMessages'] != false,
      maxProactivePerDay: readInt('maxProactivePerDay', 2, 0, 4),
    );
  }
}

class SettingsStorageService {
  Future<File> _settingsFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/chat_settings.json');
  }

  Future<ChatSettings> loadSettings() async {
    final file = await _settingsFile();
    if (!await file.exists()) {
      const defaults = ChatSettings();
      await saveSettings(defaults);
      return defaults;
    }

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return const ChatSettings();

    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const ChatSettings();
    return ChatSettings.fromJson(decoded);
  }

  Future<void> saveSettings(ChatSettings settings) async {
    final file = await _settingsFile();
    await file.writeAsString(jsonEncode(settings.toJson()), flush: true);
  }
}
