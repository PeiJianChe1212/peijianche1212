import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/config/peilink_runtime.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/pages/peilink/create_group_chat_page.dart';
import 'package:peijianche_app/services/character_registry_service.dart';

/// Regression coverage for the real-device "创建中卡死" blocker:
/// callers push CreateGroupChatPage with Navigator.push<bool>, so the page must
/// pop a bool (not the GroupChat object) or the pop itself throws and the page
/// stays in the loading state forever.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documents;

  setUp(() async {
    PeiLinkRuntime.configure(PeiLinkBuild.unspecified);
    documents = await Directory.systemTemp.createTemp('group_create_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return documents.path;
          }
          return null;
        });
  });

  tearDown(() async {
    PeiLinkRuntime.configure(PeiLinkBuild.unspecified);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    try {
      if (await documents.exists()) await documents.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> settle(WidgetTester tester, {int rounds = 25}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pump();
  }

  /// 既有页面存在其它 ListTile 装饰断言，统一排空以免干扰本回归测试。
  void drain(WidgetTester tester) {
    while (tester.takeException() != null) {}
  }

  AiCharacter character(String id) => AiCharacter(
    id: id,
    characterName: id,
    remark: '',
    createdAt: DateTime.utc(2026, 1, 1),
  );

  Future<void> seedCharacters(WidgetTester tester) async {
    await tester.runAsync(() async {
      await CharacterRegistryService().saveCharacters([
        character('q'),
        character('w'),
        character('e'),
      ]);
    });
  }

  /// 与 PeiLinkHomePage / AddAiPage 完全一致的调用方式：push<bool>。
  Future<bool?> Function() openWithBoolResult(WidgetTester tester) {
    final captured = <bool?>[];
    return () async => captured.isEmpty ? null : captured.first;
  }

  testWidgets('3 个成员可创建成功：loading 结束、页面返回、数据落盘', (tester) async {
    await seedCharacters(tester);
    bool? popResult;
    var returned = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  popResult = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CreateGroupChatPage(),
                    ),
                  );
                  returned = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await settle(tester);
    drain(tester);
    expect(find.byType(CreateGroupChatPage), findsOneWidget);
    expect(find.text('创建中'), findsNothing);

    // 选 3 个角色
    for (final id in ['q', 'w', 'e']) {
      final tile = find.byWidgetPredicate(
        (widget) => widget is CheckboxListTile && widget.value == false,
      );
      await tester.tap(tile.first);
      await tester.pump();
      expect(id, isNotEmpty);
    }
    expect(find.textContaining('3人'), findsOneWidget);

    await tester.tap(find.text('完成'));
    await tester.pump();
    // loading 立即进入
    expect(find.text('创建中'), findsOneWidget);

    await settle(tester);

    // 成功路径：loading 结束 + 页面返回 + 返回值是 bool
    expect(find.byType(CreateGroupChatPage), findsNothing);
    expect(returned, isTrue);
    expect(popResult, isTrue);

    // group_chats.json 正常写入且只有一个群、三个成员
    final file = File('${documents.path}/group_chats.json');
    expect(file.existsSync(), isTrue);
    final decoded = jsonDecode(file.readAsStringSync()) as List;
    expect(decoded, hasLength(1));
    final group = decoded.single as Map;
    expect((group['members'] as List), hasLength(3));
    expect((group['name'] as String), isNotEmpty);
    expect((group['id'] as String).startsWith('group_'), isTrue);
  });

  testWidgets('重复创建产生唯一 groupId，不产生重复半成品', (tester) async {
    await seedCharacters(tester);
    for (var round = 0; round < 2; round++) {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CreateGroupChatPage(),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is CheckboxListTile && widget.value == false,
        ).at(0),
      );
      await tester.pump();
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is CheckboxListTile && widget.value == false,
        ).at(0),
      );
      await tester.pump();
      await tester.tap(find.text('完成'));
      await settle(tester);
      drain(tester);
      expect(find.byType(CreateGroupChatPage), findsNothing);
    }

    final decoded =
        jsonDecode(File('${documents.path}/group_chats.json').readAsStringSync())
            as List;
    expect(decoded, hasLength(2));
    final ids = decoded.map((item) => (item as Map)['id']).toSet();
    expect(ids, hasLength(2), reason: 'groupId 必须唯一');
  });
}
