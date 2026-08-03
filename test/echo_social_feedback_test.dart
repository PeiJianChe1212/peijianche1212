import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/models/character_relationship.dart';
import 'package:peijianche_app/models/echo_comment.dart';
import 'package:peijianche_app/models/echo_interaction_stats.dart';
import 'package:peijianche_app/services/echo_relationship_engine_service.dart';

void main() {
  test('comment business types use stable persisted values', () {
    final comment = EchoComment(
      id: 'c1',
      echoId: 'e1',
      authorType: EchoCommentAuthorType.world,
      content: '很好看。',
      createdAt: DateTime(2026, 8, 2),
      commentType: EchoCommentType.virtualUser,
    );

    expect(comment.toJson()['commentType'], 'virtual_user');
    expect(
      EchoComment.fromJson(comment.toJson()).commentType,
      EchoCommentType.virtualUser,
    );
  });

  test('simulated and real likes remain separately persisted', () {
    const stats = EchoInteractionStats(
      echoId: 'e1',
      viewCount: 120,
      likeCount: 20,
      commentCount: 4,
      collectCount: 3,
      heatLevel: EchoHeatLevel.calm,
      realLikeCount: 1,
      virtualLikeCount: 19,
    );
    final restored = EchoInteractionStats.fromJson(stats.toJson());
    expect(restored.realLikeCount, 1);
    expect(restored.virtualLikeCount, 19);
  });

  test('relationship engine makes friends more likely than strangers', () {
    final now = DateTime(2026, 8, 2);
    final author = _character('a', now);
    final commenter = _character('b', now);
    final relationship = CharacterRelationship(
      id: CharacterRelationship.buildId('a', 'b'),
      characterIdA: 'a',
      characterIdB: 'b',
      stage: CharacterRelationshipStage.friend,
      sharedEventCount: 8,
      createdAt: now.subtract(const Duration(days: 120)),
      updatedAt: now,
    );
    const engine = EchoRelationshipEngineService();
    final friend = engine.evaluate(
      author: author,
      commenter: commenter,
      relationship: relationship,
      now: now,
    );
    final stranger = engine.evaluate(
      author: author,
      commenter: commenter,
      now: now,
    );
    expect(friend.kind, EchoRelationshipKind.friend);
    expect(friend.probability, greaterThan(stranger.probability));
    expect(friend.intimacy, greaterThan(stranger.intimacy));
  });
}

AiCharacter _character(String id, DateTime now) =>
    AiCharacter(id: id, characterName: id, remark: '', createdAt: now);
