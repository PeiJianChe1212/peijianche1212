import '../hosting/character_host_agent.dart';

/// Compatibility name for the early prototype. Batch 01 intentionally keeps
/// host rendering deterministic; a model must never decide game semantics.
@Deprecated('Use DeterministicCharacterHostResponseRenderer.')
class ModelGameCharacterTurnGateway implements CharacterHostResponseRenderer {
  const ModelGameCharacterTurnGateway();

  @override
  Future<String> render(CharacterHostRenderRequest request) async =>
      request.view.semanticResult.canonicalText;
}
