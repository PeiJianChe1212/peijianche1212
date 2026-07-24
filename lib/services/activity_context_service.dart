import '../models/activity_status.dart';
import 'activity_service.dart';
import 'life_moment_storage_service.dart';

class ActivityContextService {
  const ActivityContextService({required this.characterId});

  final String characterId;

  Future<ActivityStatus> resolve({DateTime? now}) async {
    final time = now ?? DateTime.now();
    final moments = await LifeMomentStorageService(
      characterId: characterId,
    ).loadItems();
    final recent = moments.isEmpty ? null : moments.first;
    return ActivityService(characterId: characterId).current(
      now: time,
      characterId: characterId,
      recentMoment: recent,
    );
  }
}
