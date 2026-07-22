import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/api_settings.dart';

class ApiSettingsStorageService {
  ApiSettingsStorageService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _providerKey = 'api_provider';
  static const _apiKeyKey = 'api_key';
  static const _baseUrlKey = 'api_base_url';
  static const _modelKey = 'api_model';

  Future<ApiSettings> loadSettings() async {
    final values = await _storage.readAll();
    return ApiSettings(
      provider: values[_providerKey] ?? 'DeepSeek',
      apiKey: values[_apiKeyKey] ?? '',
      baseUrl:
          values[_baseUrlKey] ?? 'https://api.deepseek.com/v1/chat/completions',
      model: values[_modelKey] ?? 'deepseek-chat',
    );
  }

  Future<void> saveSettings(ApiSettings settings) async {
    await Future.wait([
      _storage.write(key: _providerKey, value: settings.provider.trim()),
      _storage.write(key: _apiKeyKey, value: settings.apiKey.trim()),
      _storage.write(key: _baseUrlKey, value: settings.baseUrl.trim()),
      _storage.write(key: _modelKey, value: settings.model.trim()),
    ]);
  }

  Future<void> clearApiKey() async {
    await _storage.delete(key: _apiKeyKey);
  }
}
