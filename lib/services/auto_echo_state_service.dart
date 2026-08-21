import 'dart:convert';

import '../models/auto_echo_state.dart';
import 'character_scope_service.dart';

class AutoEchoStateService {
  AutoEchoStateService({required this.characterId});
  final String characterId;

  Future<AutoEchoState> load({DateTime? now}) async {
    final time = now ?? DateTime.now();
    final file = await CharacterScopeService(
      characterId,
    ).dataFile('auto_echo_state.json');
    if (!await file.exists()) return AutoEchoState.initial(time);
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return AutoEchoState.initial(time);
      return AutoEchoState.fromJson(decoded).normalized(time);
    } catch (_) {
      return AutoEchoState.initial(time);
    }
  }

  Future<void> save(AutoEchoState state) async {
    final file = await CharacterScopeService(
      characterId,
    ).dataFile('auto_echo_state.json');
    await file.writeAsString(jsonEncode(state.toJson()), flush: true);
  }

  Future<void> clear() async {
    final file = await CharacterScopeService(
      characterId,
    ).dataFile('auto_echo_state.json');
    if (await file.exists()) await file.delete();
  }
}
