import 'auto_echo_state_service.dart';
import 'decision_history_service.dart';
import 'echo_comment_interaction_storage_service.dart';
import 'echo_comment_reaction_storage_service.dart';
import 'echo_comment_storage_service.dart';
import 'echo_image_storage_service.dart';
import 'echo_interaction_stats_service.dart';
import 'echo_storage_service.dart';
import 'echo_visitor_storage_service.dart';
import 'life_event_pool_service.dart';
import 'life_moment_storage_service.dart';

/// Clears one character's generated life-cycle data while preserving its
/// definition, user configuration, long-term memory and shared records.
class CharacterRuntimeLifecycleService {
  CharacterRuntimeLifecycleService({required this.characterId});

  final String characterId;

  Future<void> clearGeneratedLife() async {
    final echoStorage = EchoStorageService(characterId: characterId);
    final echoes = await echoStorage.loadItems();
    final echoIds = echoes.map((item) => item.id).toSet();
    final imagePaths = echoes.expand((item) => item.imagePaths).toSet();

    // Per-Echo deletion also removes delayed comment/reply tasks from the
    // shared queues without touching tasks belonging to another character.
    for (final echo in echoes) {
      await echoStorage.deleteItem(echo.id);
    }

    await Future.wait([
      echoStorage.clear(),
      EchoCommentStorageService(ownerId: characterId).clear(),
      EchoInteractionStatsService(ownerId: characterId).clear(),
      EchoCommentReactionStorageService(ownerId: characterId).clear(),
      EchoVisitorStorageService(ownerId: characterId).clear(),
      EchoImageStorageService(
        characterId: characterId,
      ).clearAll(knownPaths: imagePaths),
      EchoCommentInteractionStorageService().removeForEchoIds(echoIds),
      LifeMomentStorageService(characterId: characterId).clear(),
      LifeEventPoolService(characterId: characterId).clear(),
      DecisionHistoryService(characterId: characterId).clear(),
      AutoEchoStateService(characterId: characterId).clear(),
    ]);
  }
}
