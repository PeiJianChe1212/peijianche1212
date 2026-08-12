import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/peilink_runtime.dart';
import '../models/api_settings.dart';

class ApiSettingsStorageService {
  ApiSettingsStorageService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _providerKey = 'api_provider';
  static const _apiKeyKey = 'api_key';
  static const _baseUrlKey = 'api_base_url';
  static const _modelKey = 'api_model';

  static const _multimodalApiKeyKey = 'multimodal_api_key';
  static const _multimodalBaseUrlKey = 'multimodal_base_url';
  static const _multimodalModelKey = 'multimodal_model';

  static const _imageApiKeyKey = 'image_api_key';
  static const _imageBaseUrlKey = 'image_base_url';
  static const _imageModelKey = 'image_model';

  static String _key(String key) => PeiLinkRuntime.secureStorageKey(key);

  Future<ApiSettings> loadSettings() async {
    final values = await _storage.readAll();
    return ApiSettings(
      provider: values[_key(_providerKey)] ?? 'DeepSeek',
      apiKey: values[_key(_apiKeyKey)] ?? '',
      baseUrl:
          values[_key(_baseUrlKey)] ??
          'https://api.deepseek.com/v1/chat/completions',
      model: values[_key(_modelKey)] ?? 'deepseek-chat',
      multimodalApiKey: values[_key(_multimodalApiKeyKey)] ?? '',
      multimodalBaseUrl:
          values[_key(_multimodalBaseUrlKey)] ??
          'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
      multimodalModel: values[_key(_multimodalModelKey)] ?? '',
      imageApiKey: values[_key(_imageApiKeyKey)] ?? '',
      imageBaseUrl:
          values[_key(_imageBaseUrlKey)] ??
          'https://ark.cn-beijing.volces.com/api/v3/images/generations',
      imageModel: values[_key(_imageModelKey)] ?? '',
    );
  }

  Future<void> saveSettings(ApiSettings settings) async {
    await Future.wait([
      _storage.write(key: _key(_providerKey), value: settings.provider.trim()),
      _storage.write(key: _key(_apiKeyKey), value: settings.apiKey.trim()),
      _storage.write(key: _key(_baseUrlKey), value: settings.baseUrl.trim()),
      _storage.write(key: _key(_modelKey), value: settings.model.trim()),
      _storage.write(
        key: _key(_multimodalApiKeyKey),
        value: settings.multimodalApiKey.trim(),
      ),
      _storage.write(
        key: _key(_multimodalBaseUrlKey),
        value: settings.multimodalBaseUrl.trim(),
      ),
      _storage.write(
        key: _key(_multimodalModelKey),
        value: settings.multimodalModel.trim(),
      ),
      _storage.write(
        key: _key(_imageApiKeyKey),
        value: settings.imageApiKey.trim(),
      ),
      _storage.write(
        key: _key(_imageBaseUrlKey),
        value: settings.imageBaseUrl.trim(),
      ),
      _storage.write(
        key: _key(_imageModelKey),
        value: settings.imageModel.trim(),
      ),
    ]);
  }

  Future<void> clearApiKey() async {
    await Future.wait([
      _storage.delete(key: _key(_apiKeyKey)),
      _storage.delete(key: _key(_multimodalApiKeyKey)),
      _storage.delete(key: _key(_imageApiKeyKey)),
    ]);
  }
}
