import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/peilink_runtime.dart';
import '../models/image_generation_settings.dart';
import 'api_settings_storage_service.dart';

class ImageGenerationSettingsStorageService {
  ImageGenerationSettingsStorageService({
    FlutterSecureStorage? storage,
    ApiSettingsStorageService? apiSettingsStorage,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _apiSettingsStorage = apiSettingsStorage ?? ApiSettingsStorageService();

  final FlutterSecureStorage _storage;
  final ApiSettingsStorageService _apiSettingsStorage;

  static String _key(String value) => PeiLinkRuntime.secureStorageKey(value);

  Future<ImageGenerationSettings> loadSettings() async {
    final stored = await _storage.readAll();
    final values = <String, String>{};
    for (final key in const [
      'image_generation_provider',
      'image_generation_api_key',
      'image_generation_key_source',
      'image_generation_base_url',
      'image_generation_model',
      'image_generation_protocol',
      'image_generation_capability_status',
    ]) {
      final value = stored[_key(key)];
      if (value != null) values[key] = value;
    }
    return ImageGenerationSettingsCodec.decode(
      values,
      legacySettings: await _apiSettingsStorage.loadSettings(),
    );
  }

  Future<void> saveSettings(ImageGenerationSettings settings) async {
    final values = ImageGenerationSettingsCodec.encode(settings);
    await Future.wait(
      values.entries.map(
        (entry) => _storage.write(key: _key(entry.key), value: entry.value),
      ),
    );
  }
}
