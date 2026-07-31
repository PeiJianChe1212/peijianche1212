import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/group_message.dart';

class GroupMessageStorageService {
  GroupMessageStorageService({required this.groupId});

  final String groupId;

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    final groupDirectory = Directory('${directory.path}/group_chats/$groupId');
    if (!await groupDirectory.exists()) {
      await groupDirectory.create(recursive: true);
    }
    return File('${groupDirectory.path}/messages.json');
  }

  Future<List<GroupMessage>> loadMessages() async {
    final file = await _file();
    if (!await file.exists()) return [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map(GroupMessage.fromJson)
          .where((message) => message.groupId == groupId)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveMessages(List<GroupMessage> messages) async {
    final file = await _file();
    await file.writeAsString(
      jsonEncode(messages.map((message) => message.toJson()).toList()),
      flush: true,
    );
  }

  Future<void> clearMessages() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }

  Future<void> deleteGroupDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    final groupDirectory = Directory('${directory.path}/group_chats/$groupId');
    if (await groupDirectory.exists()) {
      await groupDirectory.delete(recursive: true);
    }
  }
}
