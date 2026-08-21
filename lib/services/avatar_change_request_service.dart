import 'dart:convert';
import 'dart:math';

import 'character_scope_service.dart';

class AvatarChangeDecision {
  const AvatarChangeDecision({required this.accepted, required this.forced});
  final bool accepted;
  final bool forced;
}

class AvatarChangeRequestService {
  AvatarChangeRequestService({required this.characterId});
  final String characterId;

  Future<AvatarChangeDecision> decide() async {
    final file = await CharacterScopeService(
      characterId,
    ).dataFile('avatar_change_state.json');
    var rejectedLastTime = false;
    if (await file.exists()) {
      try {
        final json = jsonDecode(await file.readAsString());
        rejectedLastTime = json is Map && json['rejectedLastTime'] == true;
      } catch (_) {}
    }
    final forced = rejectedLastTime;
    final accepted = forced || Random().nextDouble() < .8;
    await file.writeAsString(
      jsonEncode({'rejectedLastTime': !accepted}),
      flush: true,
    );
    return AvatarChangeDecision(accepted: accepted, forced: forced);
  }
}
