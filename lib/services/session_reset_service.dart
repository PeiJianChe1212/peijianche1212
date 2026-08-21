import 'dart:async';

import 'chat_storage_service.dart';
import 'auto_echo_service.dart';
import 'character_registry_service.dart';
import 'character_runtime_lifecycle_service.dart';
import 'initiative_service.dart';
import 'life_trace_service.dart';
import 'today_service.dart';

class SessionResetService {
  static final StreamController<String> _chatResetController =
      StreamController<String>.broadcast();

  static Stream<String> get chatResets => _chatResetController.stream;

  SessionResetService({
    this.characterId,
    ChatStorageService? chatStorage,
    TodayService? todayService,
    InitiativeService? initiativeService,
    LifeTraceService? lifeTraceService,
    CharacterRuntimeLifecycleService? runtimeLifecycleService,
    this.initializeRuntime,
  }) : _chatStorage =
           chatStorage ?? ChatStorageService(characterId: characterId),
       _todayService = todayService ?? TodayService(characterId: characterId),
       _initiativeService =
           initiativeService ?? InitiativeService(characterId: characterId),
       _lifeTraceService =
           lifeTraceService ?? LifeTraceService(characterId: characterId),
       _runtimeLifecycleService =
           runtimeLifecycleService ??
           CharacterRuntimeLifecycleService(characterId: characterId ?? '');

  final String? characterId;
  final ChatStorageService _chatStorage;
  final TodayService _todayService;
  final InitiativeService _initiativeService;
  final LifeTraceService _lifeTraceService;
  final CharacterRuntimeLifecycleService _runtimeLifecycleService;
  final Future<void> Function()? initializeRuntime;

  Future<void> clearChatOnly() async {
    await _chatStorage.clearMessages();
    _chatResetController.add(characterId ?? '');
    unawaited(_initiativeService.markAllRead());
  }

  Future<void> resetSharedStory() async {
    await _chatStorage.clearMessages();
    _chatResetController.add(characterId ?? '');
    await Future.wait([
      _todayService.clearToday(),
      _initiativeService.clear(),
      _lifeTraceService.clear(),
      _runtimeLifecycleService.clearGeneratedLife(),
    ]);
    final initialize = initializeRuntime;
    if (initialize != null) {
      await initialize();
    } else {
      await _initializeFreshRuntime();
    }
  }

  Future<void> _initializeFreshRuntime() async {
    final id = characterId?.trim() ?? '';
    if (id.isEmpty) return;
    final characters = await CharacterRegistryService().loadAllCharacters();
    for (final character in characters) {
      if (character.id != id) continue;
      await AutoEchoService().generateInitialEcho(character);
      return;
    }
  }
}
