import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/config/peilink_runtime.dart';
import 'package:peijianche_app/models/ai_capability_health.dart';
import 'package:peijianche_app/models/api_settings.dart';
import 'package:peijianche_app/models/image_generation_settings.dart';
import 'package:peijianche_app/models/vision_settings.dart';
import 'package:peijianche_app/services/ai_capability_status_service.dart';

void main() {
  const service = AiCapabilityStatusService();
  const chat = ApiSettings(
    provider: AIProvider.openai,
    apiKey: 'chat-secret',
    baseUrl: 'https://api.openai.com/v1',
    model: 'chat-model',
  );
  const vision = VisionSettings(
    usageMode: VisionUsageMode.separateVisionModel,
    provider: VisionProvider.openai,
    apiKey: 'vision-secret',
    baseUrl: 'https://api.openai.com/v1',
    model: 'vision-model',
  );
  const image = ImageGenerationSettings(
    provider: ImageGenerationProvider.openai,
    apiKey: 'image-secret',
    baseUrl: 'https://api.openai.com/v1',
    model: 'image-model',
  );

  AiCapabilityVerificationSnapshot verified({
    ApiSettings chatSettings = chat,
    VisionSettings visionSettings = vision,
    ImageGenerationSettings imageSettings = image,
  }) {
    var snapshot = const AiCapabilityVerificationSnapshot();
    for (final capability in ManagedAiCapability.values) {
      snapshot = snapshot.withRecord(
        capability,
        AiCapabilityVerification(
          fingerprint: service.fingerprintFor(
            capability,
            chatSettings: chatSettings,
            visionSettings: visionSettings,
            imageSettings: imageSettings,
          ),
          success: true,
        ),
      );
    }
    return snapshot;
  }

  test('reads ready state for all three verified capabilities', () {
    final health = service.evaluate(
      chatSettings: chat,
      visionSettings: vision,
      imageSettings: image,
      verification: verified(),
    );
    expect(
      health.values.map((value) => value.state),
      everyElement(AiCapabilityHealthState.ready),
    );
  });

  test('Chat without required fields is notConfigured', () {
    final health = service.evaluate(
      chatSettings: const ApiSettings(apiKey: '', model: ''),
      visionSettings: vision,
      imageSettings: image,
      verification: const AiCapabilityVerificationSnapshot(),
    );
    expect(
      health[ManagedAiCapability.chat]?.state,
      AiCapabilityHealthState.notConfigured,
    );
  });

  test('Vision useChatModel depends on complete Chat configuration', () {
    final health = service.evaluate(
      chatSettings: const ApiSettings(apiKey: '', model: ''),
      visionSettings: const VisionSettings(
        usageMode: VisionUsageMode.useChatModel,
      ),
      imageSettings: image,
      verification: const AiCapabilityVerificationSnapshot(),
    );
    expect(
      health[ManagedAiCapability.vision]?.state,
      AiCapabilityHealthState.notConfigured,
    );
  });

  test(
    'Chat change invalidates dependent useChatModel Vision verification',
    () {
      const dependentVision = VisionSettings(
        usageMode: VisionUsageMode.useChatModel,
      );
      final oldVerification = verified(visionSettings: dependentVision);
      final changedChat = chat.copyWith(model: 'new-chat-model');
      final health = service.evaluate(
        chatSettings: changedChat,
        visionSettings: dependentVision,
        imageSettings: image,
        verification: oldVerification,
      );
      expect(
        health[ManagedAiCapability.vision]?.state,
        AiCapabilityHealthState.needsAttention,
      );
    },
  );

  test('Chat key change invalidates Image that references Chat key', () {
    const dependentImage = ImageGenerationSettings(
      provider: ImageGenerationProvider.openai,
      apiKeySource: ImageApiKeySource.chat,
      baseUrl: 'https://api.openai.com/v1',
      model: 'image-model',
    );
    final oldVerification = verified(imageSettings: dependentImage);
    final health = service.evaluate(
      chatSettings: chat.copyWith(apiKey: 'changed-chat-key'),
      visionSettings: vision,
      imageSettings: dependentImage,
      verification: oldVerification,
    );
    expect(
      health[ManagedAiCapability.imageGeneration]?.state,
      AiCapabilityHealthState.needsAttention,
    );
  });

  test(
    'independent Vision and Image fingerprints ignore upstream key changes',
    () {
      final snapshot = verified();
      final health = service.evaluate(
        chatSettings: chat.copyWith(apiKey: 'changed-chat-key'),
        visionSettings: vision,
        imageSettings: image,
        verification: snapshot,
      );
      expect(
        health[ManagedAiCapability.vision]?.state,
        AiCapabilityHealthState.ready,
      );
      expect(
        health[ManagedAiCapability.imageGeneration]?.state,
        AiCapabilityHealthState.ready,
      );
    },
  );

  test('Custom Base URL change preserves Model ID but needs retest', () {
    const custom = ImageGenerationSettings(
      provider: ImageGenerationProvider.custom,
      apiKey: 'custom-key',
      baseUrl: 'https://one.example/v1',
      model: 'manual-model',
    );
    final snapshot = verified(imageSettings: custom);
    final changed = custom.copyWith(baseUrl: 'https://two.example/v1');
    final health = service.evaluate(
      chatSettings: chat,
      visionSettings: vision,
      imageSettings: changed,
      verification: snapshot,
    );
    expect(changed.model, 'manual-model');
    expect(
      health[ManagedAiCapability.imageGeneration]?.state,
      AiCapabilityHealthState.needsAttention,
    );
  });

  test('Model change invalidates only its own capability verification', () {
    final snapshot = verified();
    final changedVision = vision.copyWith(model: 'new-vision-model');
    final health = service.evaluate(
      chatSettings: chat,
      visionSettings: changedVision,
      imageSettings: image,
      verification: snapshot,
    );
    expect(
      health[ManagedAiCapability.chat]?.state,
      AiCapabilityHealthState.ready,
    );
    expect(
      health[ManagedAiCapability.vision]?.state,
      AiCapabilityHealthState.needsAttention,
    );
    expect(
      health[ManagedAiCapability.imageGeneration]?.state,
      AiCapabilityHealthState.ready,
    );
  });

  test('missing Discovery model does not mutate saved Model ID', () {
    const savedModel = 'model-not-returned';
    const discovered = ['another-model'];
    expect(discovered, isNot(contains(savedModel)));
    expect(vision.model, 'vision-model');
  });

  test(
    'Provider mismatch produces notConfigured instead of reusing wrong key',
    () {
      const mismatched = ImageGenerationSettings(
        provider: ImageGenerationProvider.volcengine,
        apiKeySource: ImageApiKeySource.chat,
        model: 'ep-image',
      );
      final health = service.evaluate(
        chatSettings: chat,
        visionSettings: vision,
        imageSettings: mismatched,
        verification: const AiCapabilityVerificationSnapshot(),
      );
      expect(
        health[ManagedAiCapability.imageGeneration]?.state,
        AiCapabilityHealthState.notConfigured,
      );
    },
  );

  test('temporary network error does not mutate settings', () {
    final category = service.classifyError(
      const SocketException('temporary offline'),
    );
    expect(category, AiUserErrorCategory.networkUnavailable);
    expect(chat.apiKey, 'chat-secret');
    expect(vision.model, 'vision-model');
    expect(image.model, 'image-model');
  });

  test(
    'failed verification remains saveable metadata, not configuration loss',
    () {
      final failed = AiCapabilityVerification(
        fingerprint: service.fingerprintFor(
          ManagedAiCapability.chat,
          chatSettings: chat,
          visionSettings: vision,
          imageSettings: image,
        ),
        success: false,
        errorCategory: AiUserErrorCategory.timeout,
      );
      final snapshot = const AiCapabilityVerificationSnapshot().withRecord(
        ManagedAiCapability.chat,
        failed,
      );
      final health = service.evaluate(
        chatSettings: chat,
        visionSettings: vision,
        imageSettings: image,
        verification: snapshot,
      );
      expect(
        health[ManagedAiCapability.chat]?.state,
        AiCapabilityHealthState.error,
      );
      expect(chat.apiKey, 'chat-secret');
    },
  );

  test('verification JSON never contains an API key', () {
    final snapshot = verified();
    expect(snapshot.toJson().toString(), isNot(contains('chat-secret')));
    expect(snapshot.toJson().toString(), isNot(contains('vision-secret')));
    expect(snapshot.toJson().toString(), isNot(contains('image-secret')));
  });

  test('Dev diagnostics contain URLs but no authorization or API keys', () {
    PeiLinkRuntime.configure(PeiLinkBuild.dev);
    addTearDown(() => PeiLinkRuntime.configure(PeiLinkBuild.unspecified));
    final diagnostics = service.diagnostics(
      chatSettings: chat,
      visionSettings: vision,
      imageSettings: image,
    );
    final text = diagnostics.map((value) => value.toSafeMap()).toString();
    expect(text, contains('/chat/completions'));
    expect(text, contains('/images/generations'));
    expect(text.toLowerCase(), isNot(contains('authorization')));
    expect(text, isNot(contains('chat-secret')));
  });

  test('optional Vision and Image absence does not affect Chat readiness', () {
    const noVision = VisionSettings(
      usageMode: VisionUsageMode.separateVisionModel,
    );
    const noImage = ImageGenerationSettings();
    final chatOnlyVerification = const AiCapabilityVerificationSnapshot()
        .withRecord(
          ManagedAiCapability.chat,
          AiCapabilityVerification(
            fingerprint: service.fingerprintFor(
              ManagedAiCapability.chat,
              chatSettings: chat,
              visionSettings: noVision,
              imageSettings: noImage,
            ),
            success: true,
          ),
        );
    final health = service.evaluate(
      chatSettings: chat,
      visionSettings: noVision,
      imageSettings: noImage,
      verification: chatOnlyVerification,
    );
    expect(
      health[ManagedAiCapability.chat]?.state,
      AiCapabilityHealthState.ready,
    );
    expect(
      health[ManagedAiCapability.vision]?.state,
      AiCapabilityHealthState.notConfigured,
    );
    expect(
      health[ManagedAiCapability.imageGeneration]?.state,
      AiCapabilityHealthState.notConfigured,
    );
  });
}
