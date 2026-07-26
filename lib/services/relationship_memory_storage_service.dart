import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/relationship_memory.dart';

class RelationshipMemoryStorageService {
  static const String _fileName = 'relationship_memories.json';

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<List<RelationshipMemory>> loadAll() async {
    final file = await _file();
    if (!await file.exists()) return const [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(RelationshipMemory.fromJson)
          .where((item) =>
              item.characterIdA.isNotEmpty &&
              item.characterIdB.isNotEmpty &&
              item.characterIdA != item.characterIdB)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveAll(List<RelationshipMemory> items) async {
    final file = await _file();
    await file.writeAsString(
      jsonEncode(items.map((item) => item.toJson()).toList()),
      flush: true,
    );
  }

  Future<RelationshipMemory?> find(String firstId, String secondId) async {
    final items = await loadAll();
    for (final item in items) {
      if (item.containsPair(firstId, secondId)) return item;
    }
    return null;
  }

  Future<void> save(RelationshipMemory memory) async {
    final items = await loadAll();
    final index = items.indexWhere((item) => item.id == memory.id);
    if (index >= 0) {
      items[index] = memory;
    } else {
      items.add(memory);
    }
    await saveAll(items);
  }

  Future<void> removeForCharacter(String characterId) async {
    final items = await loadAll();
    final before = items.length;
    items.removeWhere((item) =>
        item.characterIdA == characterId || item.characterIdB == characterId);
    if (before != items.length) await saveAll(items);
  }
}
