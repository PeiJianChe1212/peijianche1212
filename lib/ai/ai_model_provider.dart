import '../models/ai_capability.dart';

abstract class AiModelProvider {
  String get providerName;

  Set<AiCapability> get capabilities;

  bool supports(AiCapability capability) => capabilities.contains(capability);
}
