import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/shared_experience.dart';

class SharedExperienceStorageService {
  static const String _fileName = 'shared_experiences.json';

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<List<SharedExperience>> loadAll() async {
    final file = await _file();
    if (!await file.exists()) return const [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      final items = decoded
          .whereType<Map>()
          .map(SharedExperience.fromJson)
          .where((item) =>
              item.participantIds.length >= 2 && item.summary.isNotEmpty)
          .toList();
      items.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      return items;
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveAll(List<SharedExperience> items) async {
    final file = await _file();
    final sorted = [...items]
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    await file.writeAsString(
      jsonEncode(sorted.map((item) => item.toJson()).toList()),
      flush: true,
    );
  }

  Future<bool> containsId(String id) async {
    if (id.trim().isEmpty) return false;
    final items = await loadAll();
    return items.any((item) => item.id == id);
  }

  Future<bool> saveIfAbsent(SharedExperience experience) async {
    final items = await loadAll();
    if (items.any((item) => item.id == experience.id)) return false;
    items.add(experience);
    await saveAll(items);
    return true;
  }

  Future<List<SharedExperience>> loadForPair(
    String firstId,
    String secondId, {
    int? limit,
  }) async {
    final items = (await loadAll())
        .where((item) => item.containsPair(firstId, secondId))
        .toList();
    if (limit == null || limit <= 0 || items.length <= limit) return items;
    return items.take(limit).toList();
  }

  Future<void> removeForCharacter(String characterId) async {
    final items = await loadAll();
    final before = items.length;
    items.removeWhere((item) => item.containsParticipant(characterId));
    if (before != items.length) await saveAll(items);
  }
}
