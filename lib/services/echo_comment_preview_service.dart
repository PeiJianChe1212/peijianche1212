import '../models/echo_comment.dart';

class EchoCommentPreviewService {
  const EchoCommentPreviewService._();

  static List<EchoComment> visibleComments(List<EchoComment> comments) =>
      comments
          .where(
            (comment) =>
                !comment.isDeleted && comment.content.trim().isNotEmpty,
          )
          .toList(growable: false);

  static List<EchoComment> select(List<EchoComment> comments, {int limit = 2}) {
    if (limit <= 0) return const [];
    final indexed = visibleComments(comments).indexed.toList()
      ..sort((a, b) {
        final priority = _priority(a.$2).compareTo(_priority(b.$2));
        return priority != 0 ? priority : a.$1.compareTo(b.$1);
      });
    return indexed.take(limit).map((entry) => entry.$2).toList(growable: false);
  }

  static int _priority(EchoComment comment) => switch (comment.commentType) {
    EchoCommentType.aiCharacter => 0,
    EchoCommentType.virtualUser => 1,
    EchoCommentType.real => 2,
  };
}
