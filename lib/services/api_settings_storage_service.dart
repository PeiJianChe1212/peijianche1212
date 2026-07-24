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

  static const _multimodalApiKeyKey = 'multimodal_api_key';
  static const _multimodalBaseUrlKey = 'multimodal_base_url';
  static const _multimodalModelKey = 'multimodal_model';

  static const _imageApiKeyKey = 'image_api_key';
  static const _imageBaseUrlKey = 'image_base_url';
  static const _imageModelKey = 'image_model';

  Future<ApiSettings> loadSettings() async {
    final values = await _storage.readAll();
    return ApiSettings(
      provider: values[_providerKey] ?? 'DeepSeek',
      apiKey: values[_apiKeyKey] ?? '',
      baseUrl:
          values[_baseUrlKey] ?? 'https://api.deepseek.com/v1/chat/completions',
      model: values[_modelKey] ?? 'deepseek-chat',
      multimodalApiKey: values[_multimodalApiKeyKey] ?? '',
      multimodalBaseUrl:
          values[_multimodalBaseUrlKey] ??
          'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
      multimodalModel: values[_multimodalModelKey] ?? '',
      imageApiKey: values[_imageApiKeyKey] ?? '',
      imageBaseUrl:
          values[_imageBaseUrlKey] ??
          'https://ark.cn-beijing.volces.com/api/v3/images/generations',
      imageModel: values[_imageModelKey] ?? '',
    );
  }

  Future<void> saveSettings(ApiSettings settings) async {
    await Future.wait([
      _storage.write(key: _providerKey, value: settings.provider.trim()),
      _storage.write(key: _apiKeyKey, value: settings.apiKey.trim()),
      _storage.write(key: _baseUrlKey, value: settings.baseUrl.trim()),
      _storage.write(key: _modelKey, value: settings.model.trim()),
      _storage.write(
        key: _multimodalApiKeyKey,
        value: settings.multimodalApiKey.trim(),
      ),
      _storage.write(
        key: _multimodalBaseUrlKey,
        value: settings.multimodalBaseUrl.trim(),
      ),
      _storage.write(
        key: _multimodalModelKey,
        value: settings.multimodalModel.trim(),
      ),
      _storage.write(key: _imageApiKeyKey, value: settings.imageApiKey.trim()),
      _storage.write(
        key: _imageBaseUrlKey,
        value: settings.imageBaseUrl.trim(),
      ),
      _storage.write(key: _imageModelKey, value: settings.imageModel.trim()),
    ]);
  }

  Future<void> clearApiKey() async {
    await Future.wait([
      _storage.delete(key: _apiKeyKey),
      _storage.delete(key: _multimodalApiKeyKey),
      _storage.delete(key: _imageApiKeyKey),
    ]);
  }
}
