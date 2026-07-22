import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/chat_message.dart';

class ChatStorageService {
  Future<File> _historyFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/chat_history.json');
  }

  Future<List<ChatMessage>> loadMessages() async {
    final file = await _historyFile();
    if (!await file.exists()) return [];

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return [];

    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];

    return decoded
        .whereType<Map>()
        .map(ChatMessage.fromJson)
        .where((message) => message.content.trim().isNotEmpty)
        .toList();
  }

  Future<void> saveMessages(List<ChatMessage> messages) async {
    final file = await _historyFile();
    await file.writeAsString(
      jsonEncode(messages.map((message) => message.toJson()).toList()),
      flush: true,
    );
  }

  Future<void> clearMessages() async {
    final file = await _historyFile();
    if (await file.exists()) await file.delete();
  }
}
