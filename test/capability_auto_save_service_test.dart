import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/ai_capability_health.dart';
import 'package:peijianche_app/models/api_settings.dart';
import 'package:peijianche_app/models/image_generation_settings.dart';
import 'package:peijianche_app/models/vision_settings.dart';
import 'package:peijianche_app/services/capability_auto_save_service.dart';

void main() {
  const chat = ApiSettings(
    provider: AIProvider.deepseek,
    apiKey: 'chat-key',
    baseUrl: 'https://api.deepseek.com/v1',
    model: 'deepseek-chat',
  );
  const vision = VisionSettings(
    usageMode: VisionUsageMode.separateVisionModel,
    provider: VisionProvider.volcengine,
    apiKey: 'vision-key',
    baseUrl: 'https://ark.example/api/v3/chat/completions',
    model: 'ep-vision',
    capabilityStatus: VisionCapabilityStatus.supported,
  );
  const image = ImageGenerationSettings(
    provider: ImageGenerationProvider.volcengine,
    apiKey: 'image-key',
    baseUrl: 'https://ark.example/api/v3/images/generations',
    model: 'ep-image',
    capabilityStatus: ImageGenerationCapabilityStatus.supported,
  );

  test('successful Chat test saves only Chat then verification', () async {
    final calls = <String>[];
    final service = _service(calls);
    final result = await service.saveSuccessfulTest(
      capability: ManagedAiCapability.chat,
      chatSettings: chat,
      visionSettings: vision,
      imageSettings: image,
      verification: const AiCapabilityVerificationSnapshot(),
    );
    expect(calls, ['chat', 'verification']);
    expect(result[ManagedAiCapability.chat]?.success, isTrue);
  });

  test('successful Vision test saves only Vision then verification', () async {
    final calls = <String>[];
    final service = _service(calls);
    await service.saveSuccessfulTest(
      capability: ManagedAiCapability.vision,
      chatSettings: chat,
      visionSettings: vision,
      imageSettings: image,
      verification: const AiCapabilityVerificationSnapshot(),
    );
    expect(calls, ['vision', 'verification']);
  });

  test('successful Image test saves only Image then verification', () async {
    final calls = <String>[];
    final service = _service(calls);
    await service.saveSuccessfulTest(
      capability: ManagedAiCapability.imageGeneration,
      chatSettings: chat,
      visionSettings: vision,
      imageSettings: image,
      verification: const AiCapabilityVerificationSnapshot(),
    );
    expect(calls, ['image', 'verification']);
  });

  test(
    'a settings save failure never writes a successful verification',
    () async {
      final calls = <String>[];
      final service = CapabilityAutoSaveService(
        saveChatSettings: (_) async {
          calls.add('chat');
          throw StateError('disk unavailable');
        },
        saveVisionSettings: (_) async => calls.add('vision'),
        saveImageSettings: (_) async => calls.add('image'),
        saveVerification: (_) async => calls.add('verification'),
      );
      await expectLater(
        service.saveSuccessfulTest(
          capability: ManagedAiCapability.chat,
          chatSettings: chat,
          visionSettings: vision,
          imageSettings: image,
          verification: const AiCapabilityVerificationSnapshot(),
        ),
        throwsStateError,
      );
      expect(calls, ['chat']);
    },
  );

  test('reuse relationships are saved without copying upstream keys', () async {
    VisionSettings? savedVision;
    ImageGenerationSettings? savedImage;
    final service = CapabilityAutoSaveService(
      saveChatSettings: (_) async {},
      saveVisionSettings: (value) async => savedVision = value,
      saveImageSettings: (value) async => savedImage = value,
      saveVerification: (_) async {},
    );
    const reusedVision = VisionSettings(
      usageMode: VisionUsageMode.useChatModel,
      reuseChatApiKey: true,
    );
    const reusedImage = ImageGenerationSettings(
      provider: ImageGenerationProvider.volcengine,
      apiKeySource: ImageApiKeySource.vision,
      model: 'ep-image',
    );
    var snapshot = await service.saveSuccessfulTest(
      capability: ManagedAiCapability.vision,
      chatSettings: chat,
      visionSettings: reusedVision,
      imageSettings: reusedImage,
      verification: const AiCapabilityVerificationSnapshot(),
    );
    snapshot = await service.saveSuccessfulTest(
      capability: ManagedAiCapability.imageGeneration,
      chatSettings: chat,
      visionSettings: vision,
      imageSettings: reusedImage,
      verification: snapshot,
    );
    expect(savedVision?.apiKey, isEmpty);
    expect(savedVision?.reuseChatApiKey, isTrue);
    expect(savedImage?.apiKey, isEmpty);
    expect(savedImage?.apiKeySource, ImageApiKeySource.vision);
  });
}

CapabilityAutoSaveService _service(List<String> calls) {
  return CapabilityAutoSaveService(
    saveChatSettings: (_) async => calls.add('chat'),
    saveVisionSettings: (_) async => calls.add('vision'),
    saveImageSettings: (_) async => calls.add('image'),
    saveVerification: (_) async => calls.add('verification'),
  );
}
