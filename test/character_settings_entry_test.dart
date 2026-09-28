import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/pages/peilink/character_creation_page.dart';
import 'package:peijianche_app/pages/peilink/chat_settings_page.dart';

void main() {
  testWidgets(
    'chat settings keeps mature entries and hides unfinished chat controls',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: ChatSettingsPage(character: AiCharacter.placeholder()),
        ),
      );

      expect(find.text('角色资料'), findsNothing);
      expect(find.text('编辑角色设定'), findsOneWidget);
      expect(find.text('Memory'), findsOneWidget);
      expect(find.text('心声'), findsNothing);
      expect(find.text('导出角色'), findsOneWidget);
      expect(find.text('设置当前聊天背景'), findsOneWidget);
      expect(find.text('删除聊天记录'), findsOneWidget);
      expect(find.text('重新开始角色'), findsOneWidget);
      expect(find.text('删除角色'), findsOneWidget);

      for (final hidden in const [
        '发起群聊',
        '查找聊天记录',
        '置顶聊天',
        '特别关注',
        '隐藏会话',
        '消息免打扰',
        '清理与重置',
      ]) {
        expect(find.text(hidden), findsNothing);
      }
      expect(find.text('相处方式'), findsNothing);
      expect(find.text('人设'), findsNothing);

      await tester.tap(find.text('编辑角色设定'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final editPage = tester.widget<CharacterCreationPage>(
        find.byType(CharacterCreationPage),
      );
      expect(editPage.character?.id, AiCharacter.placeholder().id);
      expect(find.text('编辑角色设定'), findsWidgets);
    },
  );
}
