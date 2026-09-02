import 'dart:convert';
import 'dart:io';

import '../config/peilink_runtime.dart';

import '../models/relationship_memory.dart';

class RelationshipMemoryStorageService {
  static const String _fileName = 'relationship_memories.json';

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<List<RelationshipMemory>> loadAll() async {
    final file = await _file();
    // Callers update the loaded collection before persisting it again. Keep the
    // empty/error paths growable too, so the return contract is consistent
    // with the successfully decoded path (`toList()`).
    if (!await file.exists()) return <RelationshipMemory>[];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return <RelationshipMemory>[];
      return decoded
          .whereType<Map>()
          .map(RelationshipMemory.fromJson)
          .where(
            (item) =>
                item.characterIdA.isNotEmpty &&
                item.characterIdB.isNotEmpty &&
                item.characterIdA != item.characterIdB,
          )
          .toList();
    } catch (_) {
      return <RelationshipMemory>[];
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
    final file = await _file();
    if (!await file.exists()) return;
    final rows = await _readRowsForRemoval(file);
    final target = characterId.trim();
    if (target.isEmpty) return;
    final remaining = rows.where((row) {
      final first = row['characterIdA'] as String;
      final second = row['characterIdB'] as String;
      return first != target && second != target;
    }).toList();
    if (remaining.length == rows.length) return;
    await _replaceRawRows(file, remaining);
  }

  /// Validates the raw file before a destructive character cleanup.
  Future<void> validateForRemoval() async {
    final file = await _file();
    if (!await file.exists()) return;
    await _readRowsForRemoval(file);
  }

  Future<List<Map<String, dynamic>>> _readRowsForRemoval(File file) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! List) {
      throw const FormatException('Invalid relationship memories file');
    }
    final rows = <Map<String, dynamic>>[];
    for (final row in decoded) {
      if (row is! Map ||
          row['characterIdA'] is! String ||
          row['characterIdB'] is! String) {
        throw const FormatException('Invalid relationship memory row');
      }
      rows.add(Map<String, dynamic>.from(row));
    }
    return rows;
  }

  Future<void> _replaceRawRows(
    File file,
    List<Map<String, dynamic>> rows,
  ) async {
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(rows), flush: true);
    await temporary.rename(file.path);
  }
}
