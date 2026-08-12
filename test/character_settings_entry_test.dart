import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/pages/peilink/chat_settings_page.dart';

void main() {
  testWidgets(
    'chat settings exposes new profile entry without old persona entry',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: ChatSettingsPage(character: AiCharacter.peiJianChe()),
        ),
      );

      expect(find.text('角色资料'), findsOneWidget);
      expect(find.text('相处方式'), findsNothing);
      expect(find.text('人设'), findsNothing);
    },
  );
}
