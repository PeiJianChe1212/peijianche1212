import 'dart:convert';
import 'dart:io';

import '../config/peilink_runtime.dart';

class RelationshipOpportunityStateService {
  static const String _fileName = 'relationship_opportunity_state.json';

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<Map<String, DateTime>> loadLastSelectedAt() async {
    final file = await _file();
    if (!await file.exists()) return {};
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return {};
      final raw = decoded['lastSelectedAt'];
      if (raw is! Map) return {};
      final result = <String, DateTime>{};
      for (final entry in raw.entries) {
        final time = DateTime.tryParse(entry.value?.toString() ?? '');
        if (time != null) result[entry.key.toString()] = time;
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  Future<void> markSelected(String relationshipId, {DateTime? now}) async {
    final values = await loadLastSelectedAt();
    values[relationshipId] = now ?? DateTime.now();
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    values.removeWhere((_, time) => time.isBefore(cutoff));

    final file = await _file();
    await file.writeAsString(
      jsonEncode({
        'lastSelectedAt': values.map(
          (key, value) => MapEntry(key, value.toIso8601String()),
        ),
      }),
      flush: true,
    );
  }
}
