import '../models/ai_capability_health.dart';
import '../models/api_settings.dart';
import '../models/image_generation_settings.dart';
import '../models/vision_settings.dart';
import 'ai_capability_status_service.dart';

typedef SaveChatSettings = Future<void> Function(ApiSettings settings);
typedef SaveVisionSettings = Future<void> Function(VisionSettings settings);
typedef SaveImageSettings =
    Future<void> Function(ImageGenerationSettings settings);
typedef SaveVerification =
    Future<void> Function(AiCapabilityVerificationSnapshot snapshot);

class CapabilityAutoSaveService {
  const CapabilityAutoSaveService({
    required this.saveChatSettings,
    required this.saveVisionSettings,
    required this.saveImageSettings,
    required this.saveVerification,
    this.statusService = const AiCapabilityStatusService(),
  });

  final SaveChatSettings saveChatSettings;
  final SaveVisionSettings saveVisionSettings;
  final SaveImageSettings saveImageSettings;
  final SaveVerification saveVerification;
  final AiCapabilityStatusService statusService;

  Future<AiCapabilityVerificationSnapshot> saveSuccessfulTest({
    required ManagedAiCapability capability,
    required ApiSettings chatSettings,
    required VisionSettings visionSettings,
    required ImageGenerationSettings imageSettings,
    required AiCapabilityVerificationSnapshot verification,
  }) async {
    switch (capability) {
      case ManagedAiCapability.chat:
        await saveChatSettings(chatSettings);
      case ManagedAiCapability.vision:
        await saveVisionSettings(visionSettings);
      case ManagedAiCapability.imageGeneration:
        await saveImageSettings(imageSettings);
    }

    final updated = verification.withRecord(
      capability,
      AiCapabilityVerification(
        fingerprint: statusService.fingerprintFor(
          capability,
          chatSettings: chatSettings,
          visionSettings: visionSettings,
          imageSettings: imageSettings,
        ),
        success: true,
      ),
    );
    await saveVerification(updated);
    return updated;
  }
}
