import '../models/chat_message.dart';
import '../platform/media/media_store.dart';
import '../platform/media/media_store_factory.dart';
import 'chat_storage_service.dart';

/// Ephemeral view of an existing source. Never serialized into memory storage.
class ResolvedMemorySource {
  const ResolvedMemorySource({
    required this.messageId,
    this.createdAt,
    this.type,
    this.preview = '',
    this.visionPreview = '',
    this.imagePath,
    this.imageMissing = false,
  });
  final String messageId;
  final DateTime? createdAt;
  final MessageType? type;
  final String preview;
  final String visionPreview;
  final String? imagePath;
  final bool imageMissing;
  bool get available => createdAt != null;
}

class MemorySourceResolver {
  MemorySourceResolver({
    required String characterId,
    Future<List<ChatMessage>> Function()? messagesLoader,
    Future<bool> Function(String)? imageExists,
    MediaStore? mediaStore,
  }) : _messagesLoader =
           messagesLoader ??
           ChatStorageService(characterId: characterId).loadMessages,
       _imageExists =
           imageExists ?? (mediaStore ?? createDefaultMediaStore()).exists;

  final Future<List<ChatMessage>> Function() _messagesLoader;
  final Future<bool> Function(String) _imageExists;
  static const int previewCharacters = 240;

  // Deliberately accepts only chat IDs. legacySourceId is not a chat ID.
  Future<List<ResolvedMemorySource>> resolve(List<String> messageIds) async {
    if (messageIds.isEmpty) return const [];
    List<ChatMessage> messages;
    try {
      messages = await _messagesLoader();
    } catch (_) {
      messages = [];
    }
    final byId = {for (final message in messages) message.id: message};
    final result = <ResolvedMemorySource>[];
    for (final id in messageIds.toSet()) {
      final source = byId[id];
      if (source == null || source.isRecalled) {
        result.add(ResolvedMemorySource(messageId: id));
        continue;
      }
      final isImage = source.type == MessageType.image;
      final path = isImage
          ? source.metadata['imagePath']?.toString().trim() ?? ''
          : '';
      var exists = false;
      if (path.isNotEmpty) {
        try {
          exists = await _imageExists(path);
        } catch (_) {
          /* missing image */
        }
      }
      result.add(
        ResolvedMemorySource(
          messageId: id,
          createdAt: source.createdAt,
          type: source.type,
          preview: shortText(source.content),
          visionPreview: isImage
              ? shortText(
                  source.metadata['visionDescription']?.toString() ?? '',
                )
              : '',
          imagePath: exists ? path : null,
          imageMissing: isImage && !exists,
        ),
      );
    }
    return result;
  }

  static String shortText(String text) {
    final clean = text.trim();
    return clean.length <= previewCharacters
        ? clean
        : '${clean.substring(0, previewCharacters - 1)}…';
  }
}
