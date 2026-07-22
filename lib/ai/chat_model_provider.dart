import 'ai_model_provider.dart';

abstract class ChatModelProvider extends AiModelProvider {
  Future<String> complete({
    required List<Map<String, dynamic>> messages,
    required double temperature,
    required int maxTokens,
    double? topP,
  });
}
