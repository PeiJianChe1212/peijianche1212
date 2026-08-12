import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/pages/peilink/character_import_page.dart';

void main() {
  testWidgets('import page exposes file entry and isolation promise', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: CharacterImportPage()));
    await tester.pump();

    expect(find.text('导入 .pei 角色'), findsOneWidget);
    expect(find.byKey(const ValueKey('select-pei-file')), findsOneWidget);
    expect(find.textContaining('不会覆盖已有角色'), findsOneWidget);
    expect(find.textContaining('聊天、Echo、羁绊或记忆数据'), findsOneWidget);
  });
}
