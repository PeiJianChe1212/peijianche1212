import 'dart:convert';
import 'dart:io';

import '../config/peilink_runtime.dart';

import '../models/group_chat.dart';

class GroupChatStorageService {
  static const String _fileName = 'group_chats.json';

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<List<GroupChat>> loadGroups() async {
    final file = await _file();
    if (!await file.exists()) return [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map(GroupChat.fromJson)
          .where((group) => group.id.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveGroups(List<GroupChat> groups) async {
    final file = await _file();
    await file.writeAsString(
      jsonEncode(groups.map((group) => group.toJson()).toList()),
      flush: true,
    );
  }

  Future<GroupChat?> loadGroup(String groupId) async {
    final groups = await loadGroups();
    for (final group in groups) {
      if (group.id == groupId) return group;
    }
    return null;
  }

  Future<void> upsertGroup(GroupChat group) async {
    final groups = await loadGroups();
    final index = groups.indexWhere((item) => item.id == group.id);
    if (index >= 0) {
      groups[index] = group;
    } else {
      groups.add(group);
    }
    await saveGroups(groups);
  }

  Future<void> deleteGroup(String groupId) async {
    final groups = await loadGroups();
    groups.removeWhere((group) => group.id == groupId);
    await saveGroups(groups);
  }
}
