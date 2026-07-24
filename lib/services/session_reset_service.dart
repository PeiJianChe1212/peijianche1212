import 'chat_storage_service.dart';
import 'initiative_service.dart';
import 'life_trace_service.dart';
import 'memory_review_service.dart';
import 'memory_storage_service.dart';
import 'today_service.dart';

class SessionResetService {
  SessionResetService({
    this.characterId,
    ChatStorageService? chatStorage,
    MemoryStorageService? memoryStorage,
    MemoryReviewService? memoryReview,
    TodayService? todayService,
    InitiativeService? initiativeService,
    LifeTraceService? lifeTraceService,
  }) : _chatStorage =
           chatStorage ?? ChatStorageService(characterId: characterId),
       _memoryStorage =
           memoryStorage ?? MemoryStorageService(characterId: characterId),
       _memoryReview =
           memoryReview ?? MemoryReviewService(characterId: characterId),
       _todayService = todayService ?? TodayService(characterId: characterId),
       _initiativeService =
           initiativeService ?? InitiativeService(characterId: characterId),
       _lifeTraceService =
           lifeTraceService ?? LifeTraceService(characterId: characterId);

  final String? characterId;
  final ChatStorageService _chatStorage;
  final MemoryStorageService _memoryStorage;
  final MemoryReviewService _memoryReview;
  final TodayService _todayService;
  final InitiativeService _initiativeService;
  final LifeTraceService _lifeTraceService;

  Future<void> clearChatOnly() async {
    await Future.wait([
      _chatStorage.clearMessages(),
      _initiativeService.markAllRead(),
    ]);
  }

  Future<void> resetSharedStory() async {
    await Future.wait([
      _chatStorage.clearMessages(),
      _memoryStorage.saveItems(const []),
      _memoryReview.saveItems(const []),
      _todayService.clearToday(),
      _initiativeService.clear(),
      _lifeTraceService.clear(),
    ]);
  }
}
