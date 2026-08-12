import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/relationship_group.dart';

void main() {
  test('relationship groups keep custom names and character assignments', () {
    const collection = RelationshipGroupCollection(
      groups: [
        RelationshipGroup(
          id: 'adventure',
          name: '冒险伙伴',
          emoji: '⚔️',
          characterIds: ['role_a', 'role_b'],
        ),
      ],
      favoriteCharacterIds: ['role_b'],
    );

    final restored = RelationshipGroupCollection.fromJson(collection.toJson());
    expect(restored.groups.single.name, '冒险伙伴');
    expect(restored.groups.single.characterIds, ['role_a', 'role_b']);
    expect(restored.favoriteCharacterIds, ['role_b']);
  });

  test('legacy or incomplete group files remain readable', () {
    final restored = RelationshipGroupCollection.fromJson({
      'groups': [
        {'id': 'friends', 'name': '朋友'},
      ],
    });

    expect(restored.groups.single.emoji, '✨');
    expect(restored.groups.single.characterIds, isEmpty);
    expect(restored.favoriteCharacterIds, isEmpty);
  });
}
