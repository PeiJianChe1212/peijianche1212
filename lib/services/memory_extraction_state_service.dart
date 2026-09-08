import 'dart:convert';
import 'dart:io';

import '../models/memory_extraction_state.dart';
import '../platform/storage/platform_storage.dart';
import 'character_scope_service.dart';

typedef MemoryExtractionStateFileProvider =
    Future<File> Function(String characterId);

class MemoryExtractionStateService {
  const MemoryExtractionStateService({
    required this.characterId,
    this.fileProvider,
    this.platformStorage,
  });

  static const int schemaVersion = 2;
  static const String fileName = 'memory_extraction_state.json';

  final String characterId;
  final MemoryExtractionStateFileProvider? fileProvider;
  final PlatformStorage? platformStorage;

  Future<MemoryExtractionState> load() => _load(strict: false);
  Future<MemoryExtractionState> loadStrict() => _load(strict: true);

  Future<MemoryExtractionState> _load({required bool strict}) async {
    final fallback = MemoryExtractionState(characterId: characterId);
    try {
      if (!await _exists()) return fallback;
      final raw = await _readText();
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
            (state['explicitAttempts'] != null &&
                (state['explicitAttempts'] is! Map ||
                    (state['explicitAttempts'] as Map).entries.any(
                      (e) =>
                          e.key is! String ||
                          !const [
                            'attempted',
                            'success',
                            'empty',
                            'failed',
                          ].contains(e.value),
                    ))) ||
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
    final scoped = MemoryExtractionState(
      characterId: characterId,
      explicitAttempts: state.explicitAttempts,
      lastProcessedMessageId: state.lastProcessedMessageId,
      lastProcessedAt: state.lastProcessedAt,
      lastSuccessfulExtractionAt: state.lastSuccessfulExtractionAt,
      lastFailureAt: state.lastFailureAt,
      lastFailedMessageId: state.lastFailedMessageId,
    );
    await _replaceTextSafely(
      jsonEncode({'schemaVersion': schemaVersion, 'state': scoped.toJson()}),
    );
  }

  Future<File> _file() {
    final provider = fileProvider;
    if (provider != null) return provider(characterId);
    return CharacterScopeService(characterId).dataFile(fileName);
  }

  Future<(PlatformStorage, String)> _storageLocation() async {
    final scope = CharacterScopeService(characterId);
    return (
      platformStorage ?? await scope.storage(),
      await scope.dataKey(fileName),
    );
  }

  Future<bool> _exists() async {
    if (fileProvider != null) return (await _file()).exists();
    final (storage, key) = await _storageLocation();
    return storage.exists(key);
  }

  Future<String> _readText() async {
    if (fileProvider != null) return (await _file()).readAsString();
    final (storage, key) = await _storageLocation();
    return storage.readText(key);
  }

  Future<void> _replaceTextSafely(String value) async {
    if (fileProvider != null) {
      final file = await _file();
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(value, flush: true);
      await temporary.rename(file.path);
      return;
    }
    final (storage, key) = await _storageLocation();
    await storage.replaceTextSafely(key, value);
  }
}
