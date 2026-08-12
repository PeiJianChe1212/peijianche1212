import '../models/ai_character.dart';
import '../models/echo_visitor_record.dart';
import 'character_relationship_storage_service.dart';
import 'echo_visitor_storage_service.dart';
import 'shared_experience_storage_service.dart';

class EchoVisitorSocialService {
  const EchoVisitorSocialService();

  Future<List<EchoVisitorRecord>> synchronize({
    required AiCharacter owner,
    required List<AiCharacter> characters,
    DateTime? now,
  }) async {
    final time = now ?? DateTime.now();
    final candidates = <AiCharacter>[];
    final relationshipStorage = CharacterRelationshipStorageService();
    final experienceStorage = SharedExperienceStorageService();
    for (final character in characters) {
      if (character.id == owner.id) continue;
      final relationship = await relationshipStorage.find(
        owner.id,
        character.id,
      );
      final experiences = await experienceStorage.loadForPair(
        owner.id,
        character.id,
      );
      if ((relationship?.sharedEventCount ?? 0) > 0 || experiences.isNotEmpty) {
        candidates.add(character);
      }
    }
    if (candidates.isEmpty) {
      return EchoVisitorStorageService(ownerId: owner.id).load();
    }
    candidates.sort((a, b) => a.id.compareTo(b.id));
    final day = time.difference(DateTime(2024)).inDays;
    final visitor = candidates[(day + _hash(owner.id)) % candidates.length];
    return EchoVisitorStorageService(ownerId: owner.id).recordCharacterVisit(
      visitorId: visitor.id,
      visitorName: visitor.characterName,
      visitorAvatarPath: visitor.avatarPath,
      now: time,
    );
  }

  int _hash(String value) {
    var hash = 17;
    for (final unit in value.codeUnits) {
      hash = (hash * 37 + unit) & 0x7fffffff;
    }
    return hash;
  }
}
