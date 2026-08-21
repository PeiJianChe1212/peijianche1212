import 'dart:convert';

import 'character_scope_service.dart';

class EchoCommentReactionStorageService {
  EchoCommentReactionStorageService({required String ownerId})
    : _scope = CharacterScopeService(ownerId);

  static const _fileName = 'echo_comment_reactions.json';
  final CharacterScopeService _scope;

  Future<Map<String, int>> loadLikes() async {
    final file = await _scope.dataFile(_fileName);
    if (!await file.exists()) return {};
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return {};
      return decoded.map(
        (key, value) => MapEntry(
          key.toString(),
          (int.tryParse(value?.toString() ?? '') ?? 0).clamp(0, 999999),
        ),
      );
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, int>> toggle(String commentId) async {
    final likes = await loadLikes();
    final current = likes[commentId] ?? 0;
    if (current > 0) {
      likes.remove(commentId);
    } else {
      likes[commentId] = 1;
    }
    final file = await _scope.dataFile(_fileName);
    await file.writeAsString(jsonEncode(likes), flush: true);
    return likes;
  }

  Future<void> clear() async {
    final file = await _scope.dataFile(_fileName);
    if (await file.exists()) await file.delete();
  }
}
