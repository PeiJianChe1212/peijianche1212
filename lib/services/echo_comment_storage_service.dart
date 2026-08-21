import 'dart:convert';

import '../models/echo_comment.dart';
import 'character_scope_service.dart';

class EchoCommentStorageService {
  EchoCommentStorageService({required String ownerId})
    : _scope = CharacterScopeService(ownerId);

  static const String _fileName = 'echo_comments.json';
  final CharacterScopeService _scope;

  Future<List<EchoComment>> loadAll() async {
    final file = await _scope.dataFile(_fileName);
    if (!await file.exists()) return [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      final comments = decoded
          .whereType<Map>()
          .map(EchoComment.fromJson)
          .where((item) => item.id.isNotEmpty && item.echoId.isNotEmpty)
          .toList();
      comments.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return comments;
    } catch (_) {
      return [];
    }
  }

  Future<List<EchoComment>> loadForEcho(String echoId) async {
    final comments = await loadAll();
    return comments
        .where((item) => item.echoId == echoId && !item.isDeleted)
        .toList();
  }

  Future<List<EchoComment>> loadForAuthor(String authorId) async {
    final comments = await loadAll();
    return comments
        .where((item) => item.authorId == authorId && !item.isDeleted)
        .toList();
  }

  Future<void> saveAll(List<EchoComment> comments) async {
    final file = await _scope.dataFile(_fileName);
    final mutable = [...comments]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    await file.writeAsString(
      jsonEncode(mutable.map((item) => item.toJson()).toList()),
      flush: true,
    );
  }

  Future<void> add(EchoComment comment) async {
    if (comment.id.isEmpty || comment.echoId.isEmpty) return;
    final comments = await loadAll();
    if (comments.any((item) => item.id == comment.id)) return;
    comments.add(comment);
    await saveAll(comments);
  }

  Future<void> importLegacy(
    String echoId,
    List<EchoComment> legacyComments,
  ) async {
    if (legacyComments.isEmpty) return;
    final comments = await loadAll();
    final knownIds = comments.map((item) => item.id).toSet();
    var changed = false;
    for (final legacy in legacyComments) {
      if (legacy.id.isEmpty || knownIds.contains(legacy.id)) continue;
      comments.add(
        legacy.copyWith(
          echoId: echoId,
          sourceType: legacy.sourceType == EchoCommentSourceType.legacy
              ? EchoCommentSourceType.legacy
              : legacy.sourceType,
        ),
      );
      knownIds.add(legacy.id);
      changed = true;
    }
    if (changed) await saveAll(comments);
  }

  Future<void> delete(String commentId, {bool deleteReplies = true}) async {
    final comments = await loadAll();
    final next = comments.where((item) {
      if (item.id == commentId) return false;
      if (deleteReplies && item.replyToCommentId == commentId) return false;
      return true;
    }).toList();
    await saveAll(next);
  }

  Future<void> deleteForEcho(String echoId) async {
    final comments = await loadAll();
    await saveAll(comments.where((item) => item.echoId != echoId).toList());
  }

  Future<void> clear() => saveAll(const []);
}
