import 'dart:convert';
import 'dart:io';

import '../models/chat_message.dart';
import 'character_scope_service.dart';

class ChatStorageService {
  ChatStorageService({this.characterId});

  final String? characterId;

  Future<File> _historyFile() {
    return CharacterScopeService(characterId).dataFile(
      'chat_history.json',
      legacyDefaultFileName: 'chat_history.json',
    );
  }

  Future<List<ChatMessage>> loadMessages() async {
    final file = await _historyFile();
    if (!await file.exists()) return [];

    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];

      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];

      return decoded
          .whereType<Map>()
          .map(ChatMessage.fromJson)
          .where(
            (message) =>
                message.content.trim().isNotEmpty ||
                (message.type == MessageType.image &&
                    (message.metadata['imagePath']
                            ?.toString()
                            .trim()
                            .isNotEmpty ??
                        false)),
          )
          .toList();
    } catch (_) {
      return [];
    }
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
    if (await file.exists()) {
      await file.delete();
    }
  }
}
