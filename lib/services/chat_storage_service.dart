import 'dart:convert';
import '../models/chat_message.dart';
import '../platform/storage/platform_storage.dart';
import 'character_scope_service.dart';

class ChatStorageService {
  ChatStorageService({this.characterId, this.storage});

  final String? characterId;
  final PlatformStorage? storage;

  Future<(PlatformStorage, String)> _location() async {
    final scope = CharacterScopeService(characterId);
    return (
      storage ?? await scope.storage(),
      await scope.dataKey(
        'chat_history.json',
        legacyDefaultFileName: 'chat_history.json',
      ),
    );
  }

  Future<List<ChatMessage>> loadMessages() async {
    final (store, key) = await _location();
    if (!await store.exists(key)) return [];

    try {
      final raw = await store.readText(key);
      if (raw.trim().isEmpty) return [];

      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];

      return decoded
          .whereType<Map>()
          .map(ChatMessage.fromJson)
          .where(
            (message) =>
                message.content.trim().isNotEmpty ||
                (message.type == MessageType.redPacket &&
                    message.redPacket != null) ||
                (message.type == MessageType.image &&
                    (message.metadata['imagePath']
                            ?.toString()
                            .trim()
                            .isNotEmpty ??
                        false)),
          )
          .toList();
    } catch (_) {
      if (store is FailFastPlatformStorage) rethrow;
      return [];
    }
  }

  Future<void> saveMessages(List<ChatMessage> messages) async {
    final (store, key) = await _location();
    await store.writeText(
      key,
      jsonEncode(messages.map((message) => message.toJson()).toList()),
    );
  }

  /// Marks an existing message as recalled without removing its stored record.
  ///
  /// Returns `true` when the message exists (including an already recalled
  /// message), and `false` when [messageId] cannot be found.
  Future<bool> recallMessage(String messageId) async {
    final normalizedId = messageId.trim();
    if (normalizedId.isEmpty) return false;

    final messages = await loadMessages();
    final index = messages.indexWhere((message) => message.id == normalizedId);
    if (index < 0) return false;

    final message = messages[index];
    if (!message.isRecalled) {
      messages[index] = message.copyWith(messageStatus: MessageStatus.recalled);
      await saveMessages(messages);
    }
    return true;
  }

  /// Opens a red packet once and persists its original opening time.
  ///
  /// An already opened packet is returned unchanged, making this operation
  /// idempotent. Returns `null` when the message is missing or is not a valid
  /// red packet message.
  Future<ChatMessage?> openRedPacket(
    String messageId, {
    String currentUserId = 'user',
    DateTime? openedAt,
  }) async {
    final normalizedId = messageId.trim();
    if (normalizedId.isEmpty) return null;

    final messages = await loadMessages();
    final index = messages.indexWhere((message) => message.id == normalizedId);
    if (index < 0) return null;

    final message = messages[index];
    final redPacket = message.redPacket;
    if (message.type != MessageType.redPacket || redPacket == null) return null;
    final actorId = currentUserId.trim();
    if (actorId.isEmpty ||
        actorId == redPacket.senderId ||
        actorId != redPacket.receiverId) {
      return null;
    }
    if (redPacket.isOpened) return message;

    final updated = message.copyWith(
      redPacket: redPacket.copyWith(
        isOpened: true,
        openedAt: openedAt ?? DateTime.now(),
      ),
    );
    messages[index] = updated;
    await saveMessages(messages);
    return updated;
  }

  Future<void> clearMessages() async {
    final (store, key) = await _location();
    if (await store.exists(key)) await store.delete(key);
  }
}
