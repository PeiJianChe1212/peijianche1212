import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/echo_comment.dart';
import 'package:peijianche_app/services/echo_comment_preview_service.dart';

void main() {
  EchoComment comment(String id, EchoCommentType type, {bool deleted = false}) {
    return EchoComment(
      id: id,
      echoId: 'echo',
      authorType: type == EchoCommentType.aiCharacter
          ? EchoCommentAuthorType.character
          : EchoCommentAuthorType.world,
      content: 'comment $id',
      createdAt: DateTime(2026),
      commentType: type,
      isDeleted: deleted,
    );
  }

  test('preview prefers AI characters, then virtual residents', () {
    final comments = [
      comment('real', EchoCommentType.real),
      comment('virtual', EchoCommentType.virtualUser),
      comment('character', EchoCommentType.aiCharacter),
    ];

    expect(EchoCommentPreviewService.select(comments).map((item) => item.id), [
      'character',
      'virtual',
    ]);
    expect(comments.map((item) => item.id), ['real', 'virtual', 'character']);
  });

  test('deleted and empty comments do not create a preview block', () {
    final comments = [
      comment('deleted', EchoCommentType.aiCharacter, deleted: true),
      EchoComment(
        id: 'empty',
        echoId: 'echo',
        authorType: EchoCommentAuthorType.world,
        content: '   ',
        createdAt: DateTime(2026),
        commentType: EchoCommentType.virtualUser,
      ),
    ];

    expect(EchoCommentPreviewService.visibleComments(comments), isEmpty);
    expect(EchoCommentPreviewService.select(comments), isEmpty);
  });
}
