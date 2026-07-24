import 'dart:io';

import 'package:http/http.dart' as http;

import '../ai/providers/volcengine_image_provider.dart';
import 'api_settings_storage_service.dart';

class ImageGenerationService {
  ImageGenerationService({
    ApiSettingsStorageService? storage,
    http.Client? client,
  }) : _storage = storage ?? ApiSettingsStorageService(),
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  final ApiSettingsStorageService _storage;
  final http.Client _client;
  final bool _ownsClient;

  Future<String> generateAndSave({
    required String prompt,
    required Directory targetDirectory,
    String? negativePrompt,
    int width = 1024,
    int height = 1024,
  }) async {
    final settings = await _storage.loadSettings();
    final provider = VolcengineImageProvider(settings: settings, client: _client);
    final generated = await provider.generate(
      prompt: prompt,
      negativePrompt: negativePrompt,
      width: width,
      height: height,
    );

    if (!await targetDirectory.exists()) {
      await targetDirectory.create(recursive: true);
    }

    final response = await _client
        .get(Uri.parse(generated.url))
        .timeout(const Duration(seconds: 90));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('图片下载失败：HTTP ${response.statusCode}');
    }
    if (response.bodyBytes.isEmpty) throw const FormatException('下载到的图片为空。');

    final file = File(
      '${targetDirectory.path}/generated_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(response.bodyBytes, flush: true);
    return file.path;
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
