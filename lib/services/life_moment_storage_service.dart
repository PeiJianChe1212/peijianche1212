import 'dart:convert';
import 'dart:io';

import '../models/life_moment.dart';
import 'character_scope_service.dart';

class LifeMomentStorageService {
  LifeMomentStorageService({required this.characterId});

  final String characterId;

  Future<File> _file() {
    return CharacterScopeService(characterId).dataFile(
      'life_moments.json',
    );
  }

  Future<List<LifeMomentCandidate>> loadItems() async {
    final file = await _file();
    if (!await file.exists()) return [];

    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];

      final items = decoded
          .whereType<Map>()
          .map(LifeMomentCandidate.fromJson)
          .where((item) => item.event.trim().isNotEmpty)
          .toList();
      items.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      return items;
    } catch (_) {
      return [];
    }
  }

  Future<void> addItem(LifeMomentCandidate item) async {
    final items = await loadItems();
    items.removeWhere((existing) => existing.id == item.id);
    items.insert(0, item);

    // 这里只保留最近 60 个生活片段，避免长期使用后文件无限膨胀。
    final kept = items.take(60).toList();
    final file = await _file();
    await file.writeAsString(
      jsonEncode(kept.map((value) => value.toJson()).toList()),
      flush: true,
    );
  }

  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) {
      await file.delete();
    }
  }
}
