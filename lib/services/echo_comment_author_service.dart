import '../models/ai_character.dart';
import '../models/echo_comment.dart';

/// Resolves only real AI-character comments through the formal registry data.
class EchoCommentAuthorService {
  const EchoCommentAuthorService._();

  static AiCharacter? characterFor(
    EchoComment comment,
    Iterable<AiCharacter> characters,
  ) {
    if (comment.commentType != EchoCommentType.aiCharacter ||
        comment.authorType != EchoCommentAuthorType.character ||
        comment.authorId.trim().isEmpty) {
      return null;
    }
    for (final character in characters) {
      if (character.id == comment.authorId) return character;
    }
    return null;
  }
}
