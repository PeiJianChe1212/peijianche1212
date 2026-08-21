import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/api_settings.dart';
import '../models/image_generation_settings.dart';
import '../models/vision_settings.dart';
import 'api_settings_storage_service.dart';
import 'image_generation_router.dart';
import 'image_generation_settings_storage_service.dart';
import 'vision_settings_storage_service.dart';

class ImageGenerationService {
  ImageGenerationService({
    ApiSettingsStorageService? storage,
    ImageGenerationSettingsStorageService? imageSettingsStorage,
    VisionSettingsStorageService? visionSettingsStorage,
    ImageGenerationRouter? router,
    http.Client? client,
  }) : _storage = storage ?? ApiSettingsStorageService(),
       _imageSettingsStorage =
           imageSettingsStorage ?? ImageGenerationSettingsStorageService(),
       _visionSettingsStorage =
           visionSettingsStorage ?? VisionSettingsStorageService(),
       _client = client ?? http.Client(),
       _router = router ?? ImageGenerationRouter(client: client),
       _ownsClient = client == null;

  final ApiSettingsStorageService _storage;
  final ImageGenerationSettingsStorageService _imageSettingsStorage;
  final VisionSettingsStorageService _visionSettingsStorage;
  final http.Client _client;
  final ImageGenerationRouter _router;
  final bool _ownsClient;

  Future<String> generateAndSave({
    required String prompt,
    required Directory targetDirectory,
    String? negativePrompt,
    int width = 1024,
    int height = 1024,
  }) async {
    final results = await Future.wait([
      _storage.loadSettings(),
      _imageSettingsStorage.loadSettings(),
      _visionSettingsStorage.loadSettings(),
    ]);
    final chatSettings = results[0] as ApiSettings;
    final imageSettings = results[1] as ImageGenerationSettings;
    final visionSettings = results[2] as VisionSettings;
    final adapter = _router.resolve(
      settings: imageSettings,
      chatSettings: chatSettings,
      visionSettings: visionSettings,
    );
    final cleanedPrompt =
        negativePrompt == null || negativePrompt.trim().isEmpty
        ? prompt.trim()
        : '${prompt.trim()}\n避免出现：${negativePrompt.trim()}';
    final generated = await adapter.generate(
      prompt: cleanedPrompt,
      width: width,
      height: height,
    );

    if (!await targetDirectory.exists()) {
      await targetDirectory.create(recursive: true);
    }

    var imageBytes = generated.bytes;
    if (imageBytes == null) {
      final url = generated.url;
      if (url == null || url.trim().isEmpty) {
        throw const FormatException('图片生成接口没有返回可保存的图片');
      }
      final response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 90));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('图片下载失败：HTTP ${response.statusCode}');
      }
      imageBytes = response.bodyBytes;
    }
    if (imageBytes.isEmpty) throw const FormatException('生成的图片为空。');

    final file = File(
      '${targetDirectory.path}/generated_${DateTime.now().microsecondsSinceEpoch}.${generated.bytes == null ? 'jpg' : 'png'}',
    );
    await file.writeAsBytes(imageBytes, flush: true);
    return file.path;
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
