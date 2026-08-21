import 'dart:convert';
import 'dart:io';

import '../config/peilink_runtime.dart';
import '../models/anniversary_item.dart';

class AnniversaryStorageService {
  static const fileName = 'anniversaries.json';

  Future<File> _file() async =>
      File('${(await getApplicationDocumentsDirectory()).path}/$fileName');

  Future<List<AnniversaryItem>> loadAll() async {
    final file = await _file();
    if (!await file.exists()) return const [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      final items = decoded
          .whereType<Map>()
          .map(AnniversaryItem.fromJson)
          .where((item) => item.id.isNotEmpty && item.title.isNotEmpty)
          .toList();
      items.sort(_compare);
      return items;
    } catch (_) {
      return const [];
    }
  }

  Future<AnniversaryItem?> loadPinned() async {
    for (final item in await loadAll()) {
      if (item.isPinned) return item;
    }
    return null;
  }

  Future<void> upsert(AnniversaryItem item) async {
    final items = List<AnniversaryItem>.from(await loadAll());
    final index = items.indexWhere((value) => value.id == item.id);
    if (item.isPinned) {
      for (var i = 0; i < items.length; i++) {
        items[i] = items[i].copyWith(isPinned: false);
      }
    }
    if (index < 0) {
      items.add(item);
    } else {
      items[index] = item;
    }
    await _save(items);
  }

  Future<void> delete(String id) async {
    final items = List<AnniversaryItem>.from(await loadAll())
      ..removeWhere((item) => item.id == id);
    await _save(items);
  }

  Future<void> setPinned(String id) async {
    final items = (await loadAll())
        .map((item) => item.copyWith(isPinned: item.id == id))
        .toList();
    await _save(items);
  }

  Future<void> _save(List<AnniversaryItem> items) async {
    final sorted = [...items]..sort(_compare);
    await (await _file()).writeAsString(
      jsonEncode(sorted.map((item) => item.toJson()).toList()),
      flush: true,
    );
  }

  static int _compare(AnniversaryItem a, AnniversaryItem b) {
    if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
    final date = a.date.compareTo(b.date);
    return date != 0 ? date : a.createdAt.compareTo(b.createdAt);
  }
}
