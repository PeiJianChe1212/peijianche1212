import '../context_builder/red_packet_event_context.dart';
import '../models/chat_message.dart';
import 'chat_storage_service.dart';

class AiRedPacketReceiveEvent {
  const AiRedPacketReceiveEvent({required this.message});

  final ChatMessage message;

  bool get shouldGenerateReply => true;

  String buildContext() =>
      const RedPacketEventContext.received().toPromptSection();
}

class AiRedPacketEventService {
  AiRedPacketEventService({
    required this.characterId,
    ChatStorageService? storage,
  }) : _storage = storage ?? ChatStorageService(characterId: characterId);

  final String characterId;
  final ChatStorageService _storage;

  Future<AiRedPacketReceiveEvent?> receive(
    ChatMessage message, {
    DateTime? receivedAt,
  }) async {
    final packet = message.redPacket;
    if (message.type != MessageType.redPacket ||
        packet == null ||
        packet.isOpened ||
        packet.receiverId != characterId ||
        packet.senderId == characterId) {
      return null;
    }

    final opened = await _storage.openRedPacket(
      message.id,
      currentUserId: characterId,
      openedAt: receivedAt,
    );
    if (opened?.redPacket?.isOpened != true) return null;
    return AiRedPacketReceiveEvent(message: opened!);
  }
}
