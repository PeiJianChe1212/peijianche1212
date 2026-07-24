import 'dart:convert';
import 'dart:io';

import '../models/memory_item.dart';
import 'character_scope_service.dart';

class MemoryStorageService {
  MemoryStorageService({this.characterId});

  final String? characterId;

  Future<File> _memoryFile() {
    return CharacterScopeService(characterId).dataFile(
      'memories.json',
      legacyDefaultFileName: 'memories.json',
    );
  }

  Future<List<MemoryItem>> loadItems() async {
    final file = await _memoryFile();
    if (!await file.exists()) return [];

    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map(MemoryItem.fromJson)
          .where((item) => item.content.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveItems(List<MemoryItem> items) async {
    final file = await _memoryFile();
    await file.writeAsString(
      jsonEncode(items.map((item) => item.toJson()).toList()),
      flush: true,
    );
  }

  Future<void> addOrUpdateFavorite({
    required String messageId,
    required String content,
    required bool isFavorite,
  }) async {
    final items = await loadItems();
    items.removeWhere((item) => item.sourceMessageId == messageId);
    if (isFavorite) {
      items.add(
        MemoryItem(
          content: content,
          category: '收藏回复',
          sourceMessageId: messageId,
          isPinned: true,
        ),
      );
    }
    await saveItems(items);
  }

  Future<String> buildPromptSection() async {
    final items =
        (await loadItems())
            .where((item) => !item.isArchived && item.category != '收藏回复')
            .toList()
          ..sort((a, b) {
            if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
            return b.createdAt.compareTo(a.createdAt);
          });

    if (items.isEmpty) return '';

    final selected = items.take(30).toList();
    final buffer = StringBuffer('【已确认记忆】\n');
    for (final item in selected) {
      buffer.writeln('- ${item.content.trim()}');
    }
    buffer.writeln('\n自然使用这些记忆，不要逐条复述，也不要主动说明自己在读取记忆。');
    return buffer.toString();
  }
}
