import 'dart:convert';

import '../models/echo_item.dart';
import 'character_scope_service.dart';

class EchoStorageService {
  EchoStorageService({String? characterId})
    : _scope = CharacterScopeService(characterId);

  static const String _fileName = 'echo_timeline.json';
  final CharacterScopeService _scope;

  Future<List<EchoItem>> loadItems() async {
    final file = await _scope.dataFile(
      _fileName,
      legacyDefaultFileName: _fileName,
    );
    if (!await file.exists()) return [];

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      final items = decoded
          .whereType<Map>()
          .map(EchoItem.fromJson)
          .where((item) => item.id.isNotEmpty)
          .toList();
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return items;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveItems(List<EchoItem> items) async {
    final file = await _scope.dataFile(
      _fileName,
      legacyDefaultFileName: _fileName,
    );
    final sorted = [...items]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await file.writeAsString(
      jsonEncode(sorted.map((item) => item.toJson()).toList()),
      flush: true,
    );
  }

  Future<void> addItem(EchoItem item) async {
    final items = await loadItems();
    items.removeWhere((current) => current.id == item.id);
    items.add(item);
    await saveItems(items);
  }

  Future<void> updateItem(EchoItem item) async {
    final items = await loadItems();
    final index = items.indexWhere((current) => current.id == item.id);
    if (index < 0) {
      items.add(item);
    } else {
      items[index] = item;
    }
    await saveItems(items);
  }

  Future<void> deleteItem(String echoId) async {
    final items = await loadItems();
    items.removeWhere((item) => item.id == echoId);
    await saveItems(items);
  }

  Future<void> clear() => saveItems(const []);
}
