import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../ai/image_generation/image_generation_adapter.dart';
import '../ai/vision/vision_adapter.dart';
import '../config/peilink_runtime.dart';
import '../models/ai_capability_health.dart';
import '../models/api_settings.dart';
import '../models/image_generation_settings.dart';
import '../models/vision_settings.dart';
import 'model_discovery_service.dart';

class AiCapabilityStatusService {
  const AiCapabilityStatusService();

  Map<ManagedAiCapability, AiCapabilityHealth> evaluate({
    required ApiSettings chatSettings,
    required VisionSettings visionSettings,
    required ImageGenerationSettings imageSettings,
    required AiCapabilityVerificationSnapshot verification,
    ManagedAiCapability? testing,
  }) {
    return {
      ManagedAiCapability.chat: _health(
        capability: ManagedAiCapability.chat,
        complete: chatSettings.isConfigured,
        missingMessage: _chatMissing(chatSettings),
        fingerprint: fingerprintFor(
          ManagedAiCapability.chat,
          chatSettings: chatSettings,
          visionSettings: visionSettings,
          imageSettings: imageSettings,
        ),
        verification: verification[ManagedAiCapability.chat],
        testing: testing == ManagedAiCapability.chat,
      ),
      ManagedAiCapability.vision: _health(
        capability: ManagedAiCapability.vision,
        complete: _visionComplete(visionSettings, chatSettings),
        missingMessage: _visionMissing(visionSettings, chatSettings),
        fingerprint: fingerprintFor(
          ManagedAiCapability.vision,
          chatSettings: chatSettings,
          visionSettings: visionSettings,
          imageSettings: imageSettings,
        ),
        verification: verification[ManagedAiCapability.vision],
        testing: testing == ManagedAiCapability.vision,
      ),
      ManagedAiCapability.imageGeneration: _health(
        capability: ManagedAiCapability.imageGeneration,
        complete: _imageComplete(imageSettings, chatSettings, visionSettings),
        missingMessage: _imageMissing(
          imageSettings,
          chatSettings,
          visionSettings,
        ),
        fingerprint: fingerprintFor(
          ManagedAiCapability.imageGeneration,
          chatSettings: chatSettings,
          visionSettings: visionSettings,
          imageSettings: imageSettings,
        ),
        verification: verification[ManagedAiCapability.imageGeneration],
        testing: testing == ManagedAiCapability.imageGeneration,
      ),
    };
  }

  String fingerprintFor(
    ManagedAiCapability capability, {
    required ApiSettings chatSettings,
    required VisionSettings visionSettings,
    required ImageGenerationSettings imageSettings,
  }) {
    final parts = switch (capability) {
      ManagedAiCapability.chat => [
        chatSettings.provider.name,
        chatSettings.baseUrl.trim(),
        chatSettings.model.trim(),
        _secretDigest(chatSettings.apiKey),
      ],
      ManagedAiCapability.vision => [
        visionSettings.usageMode.name,
        visionSettings.provider.name,
        visionSettings.effectiveBaseUrl(chatSettings),
        visionSettings.effectiveModel(chatSettings),
        _secretDigest(visionSettings.effectiveApiKey(chatSettings)),
      ],
      ManagedAiCapability.imageGeneration => [
        imageSettings.provider.name,
        imageSettings.protocol.name,
        imageSettings.effectiveBaseUrl,
        imageSettings.model.trim(),
        imageSettings.apiKeySource.name,
        _secretDigest(
          imageSettings.effectiveApiKey(
            chatSettings: chatSettings,
            visionSettings: visionSettings,
          ),
        ),
      ],
    };
    return sha256.convert(utf8.encode(parts.join('\u001f'))).toString();
  }

  AiCapabilityHealth _health({
    required ManagedAiCapability capability,
    required bool complete,
    required String missingMessage,
    required String fingerprint,
    required AiCapabilityVerification? verification,
    required bool testing,
  }) {
    if (testing) {
      return AiCapabilityHealth(
        capability: capability,
        state: AiCapabilityHealthState.testing,
        message: '测试中',
      );
    }
    if (!complete) {
      return AiCapabilityHealth(
        capability: capability,
        state: AiCapabilityHealthState.notConfigured,
        message: missingMessage,
      );
    }
    if (verification == null || verification.fingerprint != fingerprint) {
      return AiCapabilityHealth(
        capability: capability,
        state: AiCapabilityHealthState.needsAttention,
        message: '需要重新测试',
      );
    }
    if (verification.success) {
      return AiCapabilityHealth(
        capability: capability,
        state: AiCapabilityHealthState.ready,
        message: '可用',
      );
    }
    final category = verification.errorCategory ?? AiUserErrorCategory.unknown;
    return AiCapabilityHealth(
      capability: capability,
      state: AiCapabilityHealthState.error,
      message: category.message,
      errorCategory: category,
    );
  }

  bool _visionComplete(VisionSettings vision, ApiSettings chat) {
    if (vision.usageMode == VisionUsageMode.useChatModel) {
      return chat.isConfigured;
    }
    return vision.effectiveApiKey(chat).isNotEmpty &&
        vision.effectiveBaseUrl(chat).isNotEmpty &&
        vision.model.trim().isNotEmpty;
  }

  bool _imageComplete(
    ImageGenerationSettings image,
    ApiSettings chat,
    VisionSettings vision,
  ) =>
      image
          .effectiveApiKey(chatSettings: chat, visionSettings: vision)
          .isNotEmpty &&
      image.effectiveBaseUrl.isNotEmpty &&
      image.model.trim().isNotEmpty;

  String _chatMissing(ApiSettings settings) {
    if (settings.apiKey.trim().isEmpty) return '尚未配置 API Key';
    if (settings.model.trim().isEmpty) return '尚未选择聊天模型';
    if (settings.baseUrl.trim().isEmpty) return '尚未配置服务地址';
    return '尚未配置';
  }

  String _visionMissing(VisionSettings vision, ApiSettings chat) {
    if (vision.usageMode == VisionUsageMode.useChatModel &&
        !chat.isConfigured) {
      return '需要先配置聊天模型';
    }
    if (vision.effectiveApiKey(chat).isEmpty) return '尚未配置 API Key';
    if (vision.effectiveModel(chat).isEmpty) return '尚未选择图片理解模型';
    return '尚未配置';
  }

  String _imageMissing(
    ImageGenerationSettings image,
    ApiSettings chat,
    VisionSettings vision,
  ) {
    if (image
        .effectiveApiKey(chatSettings: chat, visionSettings: vision)
        .isEmpty) {
      return '当前没有可用的 API Key';
    }
    if (image.model.trim().isEmpty) return '尚未选择图片生成模型';
    return '尚未配置';
  }

  String _secretDigest(String value) =>
      sha256.convert(utf8.encode(value.trim())).toString();

  AiUserErrorCategory classifyError(Object error) {
    if (error is VisionException) {
      return switch (error.kind) {
        VisionErrorKind.invalidApiKey => AiUserErrorCategory.invalidApiKey,
        VisionErrorKind.permissionDenied =>
          AiUserErrorCategory.permissionDenied,
        VisionErrorKind.modelUnavailable =>
          AiUserErrorCategory.modelUnavailable,
        VisionErrorKind.unsupportedImageInput =>
          AiUserErrorCategory.unsupportedCapability,
        VisionErrorKind.incompatibleProtocol =>
          AiUserErrorCategory.incompatibleProtocol,
        VisionErrorKind.networkUnavailable =>
          AiUserErrorCategory.networkUnavailable,
        VisionErrorKind.timeout => AiUserErrorCategory.timeout,
        VisionErrorKind.invalidImage => AiUserErrorCategory.invalidResponse,
        VisionErrorKind.requestFailed => AiUserErrorCategory.unknown,
      };
    }
    if (error is ImageGenerationException) {
      return switch (error.kind) {
        ImageGenerationErrorKind.invalidApiKey =>
          AiUserErrorCategory.invalidApiKey,
        ImageGenerationErrorKind.modelUnavailable =>
          AiUserErrorCategory.modelUnavailable,
        ImageGenerationErrorKind.unsupportedGeneration =>
          AiUserErrorCategory.unsupportedCapability,
        ImageGenerationErrorKind.incompatibleProtocol =>
          AiUserErrorCategory.incompatibleProtocol,
        ImageGenerationErrorKind.networkUnavailable =>
          AiUserErrorCategory.networkUnavailable,
        ImageGenerationErrorKind.timeout => AiUserErrorCategory.timeout,
        ImageGenerationErrorKind.invalidResult =>
          AiUserErrorCategory.invalidResponse,
        ImageGenerationErrorKind.requestFailed => AiUserErrorCategory.unknown,
      };
    }
    if (error is ModelDiscoveryException) {
      return switch (error.kind) {
        ModelDiscoveryErrorKind.invalidApiKey =>
          AiUserErrorCategory.invalidApiKey,
        ModelDiscoveryErrorKind.invalidBaseUrl =>
          AiUserErrorCategory.invalidBaseUrl,
        ModelDiscoveryErrorKind.networkUnavailable =>
          AiUserErrorCategory.networkUnavailable,
        ModelDiscoveryErrorKind.timeout => AiUserErrorCategory.timeout,
        ModelDiscoveryErrorKind.incompatibleResponse =>
          AiUserErrorCategory.invalidResponse,
        ModelDiscoveryErrorKind.unsupported =>
          AiUserErrorCategory.unsupportedCapability,
        ModelDiscoveryErrorKind.requestFailed => AiUserErrorCategory.unknown,
      };
    }
    if (error is SocketException) return AiUserErrorCategory.networkUnavailable;
    if (error is FormatException) return AiUserErrorCategory.invalidResponse;
    return AiUserErrorCategory.unknown;
  }

  List<AiRequestDiagnostics> diagnostics({
    required ApiSettings chatSettings,
    required VisionSettings visionSettings,
    required ImageGenerationSettings imageSettings,
  }) {
    if (!PeiLinkRuntime.developerToolsEnabled) return const [];
    String? discoveryUrl(String baseUrl) {
      try {
        return ApiEndpointResolver.modelsUrl(baseUrl);
      } catch (_) {
        return null;
      }
    }

    String safeUrl(String Function() resolve) {
      try {
        return resolve();
      } catch (_) {
        return '';
      }
    }

    return [
      AiRequestDiagnostics(
        capability: ManagedAiCapability.chat,
        provider: chatSettings.provider.label,
        model: chatSettings.model,
        requestUrl: safeUrl(() => chatSettings.chatCompletionsUrl),
        discoveryUrl: discoveryUrl(chatSettings.baseUrl),
      ),
      AiRequestDiagnostics(
        capability: ManagedAiCapability.vision,
        provider: visionSettings.usageMode == VisionUsageMode.useChatModel
            ? chatSettings.provider.label
            : visionSettings.provider.label,
        model: visionSettings.effectiveModel(chatSettings),
        requestUrl: safeUrl(
          () => ApiEndpointResolver.chatCompletionsUrl(
            visionSettings.effectiveBaseUrl(chatSettings),
          ),
        ),
        discoveryUrl: discoveryUrl(
          visionSettings.effectiveBaseUrl(chatSettings),
        ),
      ),
      AiRequestDiagnostics(
        capability: ManagedAiCapability.imageGeneration,
        provider: imageSettings.provider.label,
        model: imageSettings.model,
        requestUrl: safeUrl(
          () => ImageGenerationEndpointResolver.generationsUrl(
            imageSettings.effectiveBaseUrl,
          ),
        ),
        discoveryUrl: discoveryUrl(imageSettings.effectiveBaseUrl),
      ),
    ];
  }
}
