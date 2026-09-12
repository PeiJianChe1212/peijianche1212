import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/services/echo_expression_prompt.dart';
import 'package:peijianche_app/services/echo_text_sanitizer.dart';

void main() {
  group('social avatar compatibility', () {
    test('old characters fall back to their identity avatar', () {
      final character = AiCharacter.fromJson({
        'id': 'old-role',
        'characterName': '旧角色',
        'avatarPath': '/identity.png',
      });

      expect(character.socialAvatarPath, isEmpty);
      expect(character.effectiveSocialAvatarPath, '/identity.png');
    });

    test('social avatar does not overwrite identity avatar', () {
      final original = AiCharacter(
        id: 'role',
        characterName: '角色',
        remark: '',
        avatarPath: '/identity.png',
        createdAt: DateTime(2026),
      );
      final updated = original.copyWith(socialAvatarPath: '/social.png');

      expect(updated.avatarPath, '/identity.png');
      expect(updated.effectiveSocialAvatarPath, '/social.png');
      expect(
        AiCharacter.fromJson(updated.toJson()).socialAvatarPath,
        '/social.png',
      );
    });
  });

  group('Echo stage direction protection', () {
    test('prompt explicitly rejects parenthesized stage actions', () {
      expect(EchoExpressionPrompt.rules(), contains('禁止用括号描写动作'));
    });

    test(
      'removes leading and standalone actions but keeps prose parentheses',
      () {
        expect(EchoTextSanitizer.clean('（指尖转着蜡模）别猜了，是婚戒。'), '别猜了，是婚戒。');
        expect(EchoTextSanitizer.clean('今天完成了（第二版）设计。'), '今天完成了（第二版）设计。');
        expect(EchoTextSanitizer.clean('（周末限定）今天开门。'), '（周末限定）今天开门。');
        expect(
          EchoTextSanitizer.clean('正文第一行\n（轻轻放下杯子）\n正文第二行'),
          '正文第一行\n正文第二行',
        );
      },
    );
  });
}
