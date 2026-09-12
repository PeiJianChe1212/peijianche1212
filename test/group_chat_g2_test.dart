import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/config/peilink_runtime.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/widgets/group/group_visuals.dart';
import 'package:peijianche_app/models/group_chat.dart';
import 'package:peijianche_app/models/group_member.dart';
import 'package:peijianche_app/models/group_message.dart';
import 'package:peijianche_app/models/user_profile.dart';
import 'package:peijianche_app/pages/peilink/group_chat_page.dart';
import 'package:peijianche_app/pages/peilink/group_chat_settings_page.dart';
import 'package:peijianche_app/services/character_registry_service.dart';
import 'package:peijianche_app/services/group_chat_storage_service.dart';
import 'package:peijianche_app/services/group_message_storage_service.dart';
import 'package:peijianche_app/services/peilink_appearance_service.dart';
import 'package:peijianche_app/services/user_profile_storage_service.dart';

/// Phase G2 targeted coverage: user identity in members + settings/chat visuals.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documents;

  setUp(() async {
    PeiLinkRuntime.configure(PeiLinkBuild.unspecified);
    documents = await Directory.systemTemp.createTemp('group_g2_test_');
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

  void drain(WidgetTester tester) {
    while (tester.takeException() != null) {}
  }

  AiCharacter character(String id) => AiCharacter(
    id: id,
    characterName: id,
    remark: '',
    createdAt: DateTime.utc(2026, 1, 1),
  );

  Future<void> seed(WidgetTester tester, {String nickname = '念念'}) async {
    await tester.runAsync(() async {
      await CharacterRegistryService().saveCharacters([
        character('q'),
        character('w'),
        character('e'),
      ]);
      await UserProfileStorageService().saveProfile(
        UserProfile(nickname: nickname),
      );
      await GroupChatStorageService().upsertGroup(
        GroupChat(
          id: 'group_1',
          name: 'q、w、e',
          createdAt: DateTime.utc(2026, 8, 1),
          lastActiveAt: DateTime.utc(2026, 8, 1),
          members: [
            for (final id in ['q', 'w', 'e'])
              GroupMember(
                groupId: 'group_1',
                characterId: id,
                joinedAt: DateTime.utc(2026, 8, 1),
              ),
          ],
        ),
      );
      await GroupMessageStorageService(groupId: 'group_1').saveMessages([
        GroupMessage(
          id: 'm1',
          groupId: 'group_1',
          senderType: GroupSenderType.user,
          senderId: 'user',
          content: '大家好',
          createdAt: DateTime.utc(2026, 8, 21, 9),
        ),
      ]);
    });
  }

  Future<PeiLinkAppearanceController> pump(
    WidgetTester tester,
    Widget home,
  ) async {
    final controller = await tester.runAsync(() async {
      final c = PeiLinkAppearanceController.testing(
        fileProvider: () async => File('${documents.path}/appearance.json'),
      );
      await c.load();
      return c;
    });
    await tester.pumpWidget(
      PeiLinkAppearanceScope(
        controller: controller!,
        child: MaterialApp(home: home),
      ),
    );
    await settle(tester);
    drain(tester);
    return controller;
  }

  Map<String, dynamic> storedGroup() =>
      (jsonDecode(File('${documents.path}/group_chats.json').readAsStringSync())
                  as List)
              .firstWhere((item) => (item as Map)['id'] == 'group_1')
          as Map<String, dynamic>;

  testWidgets('群聊顶栏：群名 + 4 人副信息', (tester) async {
    await seed(tester);
    await pump(tester, const GroupChatPage(groupId: 'group_1'));

    expect(find.text('q、w、e'), findsWidgets);
    expect(find.text('4 人'), findsOneWidget);
    expect(find.text('q、w、e (4)'), findsNothing);
  });

  testWidgets('设置页显示 用户自己 + 3 AI + 管理入口', (tester) async {
    await seed(tester);
    await pump(tester, const GroupChatSettingsPage(groupId: 'group_1'));

    expect(find.byKey(const ValueKey('group-member-self')), findsOneWidget);
    // 昵称同时出现在成员卡片与「我的群聊身份」设置项
    expect(find.text('念念'), findsWidgets);
    expect(find.text('4 人'), findsOneWidget);
    for (final id in ['q', 'w', 'e']) {
      expect(find.text(id), findsWidgets);
    }
    expect(find.byKey(const ValueKey('group-member-manage')), findsOneWidget);
    expect(find.text('管理'), findsOneWidget);
  });

  testWidgets('用户资料为空时用现有 fallback，不硬编码角色', (tester) async {
    await seed(tester, nickname: '未设置');
    await pump(tester, const GroupChatSettingsPage(groupId: 'group_1'));
    expect(find.text('我'), findsWidgets);
  });

  testWidgets('成员管理只管理 AI：用户不可删，AI 仍可增删', (tester) async {
    await seed(tester);
    await pump(tester, const GroupChatSettingsPage(groupId: 'group_1'));

    await tester.tap(find.byKey(const ValueKey('group-member-manage')));
    await settle(tester, rounds: 20);
    drain(tester);

    expect(find.byType(GroupMemberChoice), findsNWidgets(4));
    final locked = find.byWidgetPredicate(
      (widget) => widget is GroupMemberChoice && widget.locked,
    );
    expect(locked, findsOneWidget);
    expect(tester.widget<GroupMemberChoice>(locked).name, '念念');
    expect(tester.widget<GroupMemberChoice>(locked).selected, isTrue);
    expect(tester.widget<GroupMemberChoice>(locked).onTap, isNull);
    await tester.tap(locked);
    await tester.pump();
    expect(tester.widget<GroupMemberChoice>(locked).selected, isTrue);

    Finder member(String id) => find.byKey(ValueKey('manage-member-$id'));
    await tester.tap(member('q'));
    await tester.pump();
    expect(tester.widget<GroupMemberChoice>(member('q')).selected, isFalse);
    await tester.tap(member('w'));
    await tester.pump();
    final done = find.widgetWithText(TextButton, '完成');
    expect(tester.widget<TextButton>(done).onPressed, isNull);
    await tester.tap(member('w'));
    await tester.pump();
    expect(tester.widget<GroupMemberChoice>(member('w')).selected, isTrue);
    expect(tester.widget<TextButton>(done).onPressed, isNotNull);
    await tester.tap(find.text('完成'));
    await settle(tester, rounds: 20);
    drain(tester);

    expect((storedGroup()['members'] as List), hasLength(2));
    expect(find.text('3 人'), findsOneWidget);
  });

  testWidgets('基础设置：免打扰/置顶保存逻辑不变', (tester) async {
    await seed(tester);
    await pump(tester, const GroupChatSettingsPage(groupId: 'group_1'));

    await tester.tap(find.text('消息免打扰'));
    await settle(tester, rounds: 20);
    drain(tester);
    expect(storedGroup()['isMuted'], isTrue);

    await tester.tap(find.text('置顶聊天'));
    await settle(tester, rounds: 20);
    drain(tester);
    expect(storedGroup()['isPinned'], isTrue);
  });

  testWidgets('清空聊天记录与删除并退出逻辑不变，弹窗为二次确认', (tester) async {
    await seed(tester);
    await pump(tester, const GroupChatSettingsPage(groupId: 'group_1'));

    await tester.ensureVisible(find.text('清空聊天记录'));
    await tester.tap(find.text('清空聊天记录'));
    await settle(tester, rounds: 12);
    expect(find.text('清空'), findsOneWidget);
    await tester.tap(find.text('清空'));
    await settle(tester, rounds: 20);
    drain(tester);
    final messages = await tester.runAsync(
      () => GroupMessageStorageService(groupId: 'group_1').loadMessages(),
    );
    expect(messages, isEmpty);

    await tester.ensureVisible(find.text('删除并退出群聊'));
    await tester.tap(find.text('删除并退出群聊'));
    await settle(tester, rounds: 12);
    expect(find.widgetWithText(FilledButton, '删除并退出'), findsOneWidget);
    await tester.tap(find.text('删除并退出'));
    await settle(tester, rounds: 20);
    drain(tester);
    final groups = await tester.runAsync(
      () => GroupChatStorageService().loadGroups(),
    );
    expect(groups!, isEmpty);
  });

  test('storage schema 未新增字段（群/成员 JSON 键集合不变）', () async {
    final group = GroupChat(
      id: 'g',
      name: 'n',
      createdAt: DateTime.utc(2026, 1, 1),
      lastActiveAt: DateTime.utc(2026, 1, 1),
      members: [
        GroupMember(
          groupId: 'g',
          characterId: 'q',
          joinedAt: DateTime.utc(2026, 1, 1),
        ),
      ],
    );
    expect(group.toJson().keys.toSet(), {
      'id',
      'name',
      'avatarPath',
      'members',
      'createdAt',
      'lastMessage',
      'lastMessageAt',
      'lastActiveAt',
      'unreadCount',
      'isPinned',
      'isMuted',
      'summaryContext',
      'currentTopic',
      'heat',
    });
    expect(group.members.first.toJson().keys.toSet(), {
      'groupId',
      'characterId',
      'groupNickname',
      'allowInitiative',
      'activityLevel',
      'joinedAt',
      'relationshipLabel',
      'lastSpokeAt',
    });
  });
}
