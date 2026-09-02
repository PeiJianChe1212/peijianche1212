import 'dart:convert';
import 'dart:io';

import '../models/memory_extraction_state.dart';
import 'character_scope_service.dart';

typedef MemoryExtractionStateFileProvider =
    Future<File> Function(String characterId);

class MemoryExtractionStateService {
  const MemoryExtractionStateService({
    required this.characterId,
    this.fileProvider,
  });

  static const int schemaVersion = 2;
  static const String fileName = 'memory_extraction_state.json';

  final String characterId;
  final MemoryExtractionStateFileProvider? fileProvider;

  Future<MemoryExtractionState> load() => _load(strict: false);
  Future<MemoryExtractionState> loadStrict() => _load(strict: true);

  Future<MemoryExtractionState> _load({required bool strict}) async {
    final fallback = MemoryExtractionState(characterId: characterId);
    try {
      final file = await _file();
      if (!await file.exists()) return fallback;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        if (strict) throw const FormatException('Empty extraction state');
        return fallback;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['schemaVersion'] != schemaVersion) {
        if (strict) {
          throw const FormatException('Invalid extraction state schema');
        }
        return fallback;
      }
      final state = decoded['state'];
      if (strict) {
        if (state is! Map ||
            [
              'lastProcessedMessageId',
              'lastFailedMessageId',
            ].any((key) => state[key] != null && state[key] is! String) ||
            [
              'lastProcessedAt',
              'lastSuccessfulExtractionAt',
              'lastFailureAt',
            ].any(
              (key) =>
                  state[key] != null &&
                  (state[key] is! String ||
                      DateTime.tryParse(state[key]) == null),
            )) {
          throw const FormatException('Invalid extraction state fields');
        }
      }
      return state is Map
          ? MemoryExtractionState.fromJson(state, characterId: characterId)
          : fallback;
    } catch (_) {
      if (strict) rethrow;
      return fallback;
    }
  }

  Future<void> save(MemoryExtractionState state) async {
    await loadStrict();
    final file = await _file();
    await file.parent.create(recursive: true);
    final scoped = MemoryExtractionState(
      characterId: characterId,
      lastProcessedMessageId: state.lastProcessedMessageId,
      lastProcessedAt: state.lastProcessedAt,
      lastSuccessfulExtractionAt: state.lastSuccessfulExtractionAt,
      lastFailureAt: state.lastFailureAt,
      lastFailedMessageId: state.lastFailedMessageId,
    );
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({'schemaVersion': schemaVersion, 'state': scoped.toJson()}),
      flush: true,
    );
    await temporary.rename(file.path);
  }

  Future<File> _file() {
    final provider = fileProvider;
    if (provider != null) return provider(characterId);
    return CharacterScopeService(characterId).dataFile(fileName);
  }
}
