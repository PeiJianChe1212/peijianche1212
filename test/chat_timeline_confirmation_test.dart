import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/pages/chat_page.dart';

void main() {
  testWidgets('timeline confirmation uses compact PeiLink dialog and cancels', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<bool>(
                context: context,
                builder: (_) => const TimelineChangeConfirmationDialog(
                  title: '重新生成这条回复？',
                  content: '当前回复会被替换，后续内容可能受影响。',
                  confirmText: '重新生成',
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('当前回复会被替换，后续内容可能受影响。'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('timeline confirmation returns true only after confirmation', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<bool>(
                context: context,
                builder: (_) => const TimelineChangeConfirmationDialog(
                  title: '回溯到这里？',
                  content: '保留当前消息，删除它之后的聊天内容。',
                  confirmText: '回溯',
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('回溯'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  test(
    'rollback success snackbars are absent while error feedback remains',
    () {
      final source = File('lib/pages/chat_page.dart').readAsStringSync();
      expect(source, isNot(contains("_showSnack('已经在这里了')")));
      expect(source, isNot(contains("_showSnack(editableMessage == null")));
      expect(source, contains("_showSnack('还没有配置模型与 API，请先到设置中填写。')"));
      expect(source, contains("_showSnack('消息撤回失败')"));
    },
  );
}
