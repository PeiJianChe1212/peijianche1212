import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/memory_item.dart';
import '../models/pending_memory.dart';
import 'memory_storage_service.dart';

class MemoryReviewService {
  final MemoryStorageService _memoryStorage = MemoryStorageService();

  Future<File> _pendingFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/pending_memories.json');
  }

  Future<List<PendingMemory>> loadItems() async {
    final file = await _pendingFile();
    if (!await file.exists()) return [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map(PendingMemory.fromJson)
          .where((item) => item.content.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveItems(List<PendingMemory> items) async {
    final file = await _pendingFile();
    await file.writeAsString(
      jsonEncode(items.map((item) => item.toJson()).toList()),
      flush: true,
    );
  }

  Future<int> addCandidates(List<PendingMemory> candidates) async {
    final pending = await loadItems();
    final memories = await _memoryStorage.loadItems();
    final known = <String>{
      ...pending.map((item) => _normalize(item.content)),
      ...memories.map((item) => _normalize(item.content)),
    };
    var added = 0;
    for (final candidate in candidates) {
      final key = _normalize(candidate.content);
      if (key.isEmpty || known.contains(key)) continue;
      pending.add(candidate);
      known.add(key);
      added++;
    }
    await saveItems(pending);
    return added;
  }

  Future<void> update(PendingMemory item) async {
    final items = await loadItems();
    final index = items.indexWhere((candidate) => candidate.id == item.id);
    if (index < 0) return;
    items[index] = item;
    await saveItems(items);
  }

  Future<void> reject(String id) async {
    final items = await loadItems();
    items.removeWhere((item) => item.id == id);
    await saveItems(items);
  }

  Future<void> approve(PendingMemory item) async {
    final memories = await _memoryStorage.loadItems();
    final exists = memories.any(
      (memory) => _normalize(memory.content) == _normalize(item.content),
    );
    if (!exists) {
      memories.add(
        MemoryItem(content: item.content.trim(), category: item.category),
      );
      await _memoryStorage.saveItems(memories);
    }
    await reject(item.id);
  }

  String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[\s，。！？、,.!?]'), '');
}
