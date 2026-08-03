import '../services/memory_storage_service.dart';
import 'memory_context.dart';

/// 将现有 Memory 系统接到 Context Builder；不重做记忆存储与审核。
class ExistingMemoryContextProvider implements MemoryContextProvider {
  ExistingMemoryContextProvider({String? characterId})
    : _storage = MemoryStorageService(characterId: characterId);

  final MemoryStorageService _storage;

  @override
  Future<MemoryContext> load() async {
    return MemoryContext(confirmedMemory: await _storage.buildPromptSection());
  }
}
