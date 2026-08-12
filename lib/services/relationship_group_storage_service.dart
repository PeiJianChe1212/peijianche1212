import 'dart:convert';
import 'dart:io';

import '../config/peilink_runtime.dart';

import '../models/relationship_group.dart';

class RelationshipGroupStorageService {
  static const _fileName = 'relationship_groups.json';

  Future<File> _file() async =>
      File('${(await getApplicationDocumentsDirectory()).path}/$_fileName');

  Future<RelationshipGroupCollection> load() async {
    final file = await _file();
    if (!await file.exists()) return const RelationshipGroupCollection();
    try {
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map
          ? RelationshipGroupCollection.fromJson(decoded)
          : const RelationshipGroupCollection();
    } catch (_) {
      return const RelationshipGroupCollection();
    }
  }

  Future<void> save(RelationshipGroupCollection value) async {
    await (await _file()).writeAsString(
      jsonEncode(value.toJson()),
      flush: true,
    );
  }
}
