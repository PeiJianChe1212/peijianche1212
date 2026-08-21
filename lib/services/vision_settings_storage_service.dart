import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/peilink_runtime.dart';
import '../models/vision_settings.dart';
import 'api_settings_storage_service.dart';

class VisionSettingsStorageService {
  VisionSettingsStorageService({
    FlutterSecureStorage? storage,
    ApiSettingsStorageService? apiSettingsStorage,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _apiSettingsStorage = apiSettingsStorage ?? ApiSettingsStorageService();

  final FlutterSecureStorage _storage;
  final ApiSettingsStorageService _apiSettingsStorage;

  static String _key(String value) => PeiLinkRuntime.secureStorageKey(value);

  Future<VisionSettings> loadSettings() async {
    final stored = await _storage.readAll();
    final values = <String, String>{};
    for (final key in const [
      'vision_usage_mode',
      'vision_provider',
      'vision_api_key',
      'vision_reuse_chat_key',
      'vision_base_url',
      'vision_model',
      'vision_capability_status',
    ]) {
      final value = stored[_key(key)];
      if (value != null) values[key] = value;
    }
    return VisionSettingsCodec.decode(
      values,
      legacySettings: await _apiSettingsStorage.loadSettings(),
    );
  }

  Future<void> saveSettings(VisionSettings settings) async {
    final values = VisionSettingsCodec.encode(settings);
    await Future.wait(
      values.entries.map(
        (entry) => _storage.write(key: _key(entry.key), value: entry.value),
      ),
    );
  }
}
