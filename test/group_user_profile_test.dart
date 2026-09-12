import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/config/peilink_runtime.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/models/group_chat.dart';
import 'package:peijianche_app/models/group_member.dart';
import 'package:peijianche_app/models/group_message.dart';
import 'package:peijianche_app/models/group_user_profile.dart';
import 'package:peijianche_app/models/user_profile.dart';
import 'package:peijianche_app/pages/peilink/group_chat_page.dart';
import 'package:peijianche_app/pages/peilink/group_chat_settings_page.dart';
import 'package:peijianche_app/pages/peilink/group_user_profile_page.dart';
import 'package:peijianche_app/services/character_registry_service.dart';
import 'package:peijianche_app/services/group_chat_storage_service.dart';
import 'package:peijianche_app/services/group_message_storage_service.dart';
import 'package:peijianche_app/services/group_user_profile_storage_service.dart';
import 'package:peijianche_app/services/peilink_appearance_service.dart';
import 'package:peijianche_app/services/user_profile_storage_service.dart';

/// Phase G2.5 targeted coverage: per-group user identity + group extension entry.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documents;

  setUp(() async {
    PeiLinkRuntime.configure(PeiLinkBuild.unspecified);
    documents = await Directory.systemTemp.createTemp('group_identity_test_');
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

  Future<void> seedGroup(WidgetTester tester, String groupId) async {
    await tester.runAsync(() async {
      await GroupChatStorageService().upsertGroup(
        GroupChat(
          id: groupId,
          name: groupId,
          createdAt: DateTime.utc(2026, 8, 1),
          lastActiveAt: DateTime.utc(2026, 8, 1),
          members: [
            GroupMember(
              groupId: groupId,
              characterId: 'q',
              joinedAt: DateTime.utc(2026, 8, 1),
            ),
          ],
        ),
      );
      await GroupMessageStorageService(groupId: groupId).saveMessages([
        GroupMessage(
          id: 'm_$groupId',
          groupId: groupId,
          senderType: GroupSenderType.user,
          senderId: 'user',
          content: '旧消息',
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

  test('不同 groupId 保存不同群聊身份，互不影响', () async {
    await GroupUserProfileStorageService(groupId: 'g1').save(
      const GroupUserProfile(
        groupId: 'g1',
        displayName: '群一的念念',
        selfDescription: '大家认识很久的朋友',
      ),
    );
    await GroupUserProfileStorageService(groupId: 'g2').save(
      const GroupUserProfile(groupId: 'g2', displayName: '群二的念念'),
    );

    final g1 = await GroupUserProfileStorageService(groupId: 'g1').load();
    final g2 = await GroupUserProfileStorageService(groupId: 'g2').load();
    expect(g1.displayName, '群一的念念');
    expect(g1.selfDescription, '大家认识很久的朋友');
    expect(g2.displayName, '群二的念念');
    expect(g2.selfDescription, isEmpty);

    // 独立文件，且不碰 group_chats.json / messages.json
    expect(
      File('${documents.path}/group_chats/g1/user_profile.json').existsSync(),
      isTrue,
    );
    expect(File('${documents.path}/group_chats/g1/messages.json').existsSync(), isFalse);
  });

  test('旧群无 user_profile.json 时 fallback 到全局 UserProfile，且不写盘', () async {
    await UserProfileStorageService().saveProfile(
      const UserProfile(nickname: '念念', avatarPath: '/tmp/avatar.png'),
    );
    final storage = GroupUserProfileStorageService(groupId: 'legacy');
    final raw = await storage.load();
    expect(raw.isEmpty, isTrue);
    expect(
      File('${documents.path}/group_chats/legacy/user_profile.json').existsSync(),
      isFalse,
      reason: '仅展示时应回退，不立即写文件',
    );

    final resolved = await storage.loadResolved();
    expect(resolved.displayName, '念念');
    expect(resolved.avatarPath, '/tmp/avatar.png');

    // 编辑保存后只影响该群
    await storage.save(resolved.copyWith(displayName: '只在这个群用的名字'));
    final reloaded = await storage.loadResolved();
    expect(reloaded.displayName, '只在这个群用的名字');
    final other = await GroupUserProfileStorageService(
      groupId: 'other',
    ).loadResolved();
    expect(other.displayName, '念念');
  });

  testWidgets('设置页两个入口都进入我的群聊身份页', (tester) async {
    await tester.runAsync(() async {
      await CharacterRegistryService().saveCharacters([character('q')]);
      await UserProfileStorageService().saveProfile(
        const UserProfile(nickname: '念念'),
      );
    });
    await seedGroup(tester, 'group_1');
    await pump(tester, const GroupChatSettingsPage(groupId: 'group_1'));

    // 顶部成员区的"用户自己"卡片可点击
    await tester.tap(find.byKey(const ValueKey('group-member-self')));
    await settle(tester, rounds: 25);
    drain(tester);
    expect(find.byType(GroupUserProfilePage), findsOneWidget);
    expect(find.text('我的群聊身份'), findsWidgets);

    // 返回后走设置项入口
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await settle(tester, rounds: 10);
    drain(tester);
    await tester.tap(find.byKey(const ValueKey('group-identity-entry')));
    await settle(tester, rounds: 25);
    drain(tester);
    expect(find.byType(GroupUserProfilePage), findsOneWidget);
  });

  testWidgets('群聊 + 就地展开宫格（非 BottomSheet），首项为我的群聊身份', (tester) async {
    await tester.runAsync(() async {
      await CharacterRegistryService().saveCharacters([character('q')]);
    });
    await seedGroup(tester, 'group_1');
    await pump(tester, const GroupChatPage(groupId: 'group_1'));

    expect(find.byKey(const ValueKey('group-extension-entry')), findsOneWidget);
    expect(find.byKey(const ValueKey('group-mention-entry')), findsOneWidget);
    expect(find.byKey(const ValueKey('group-more-panel')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('group-extension-entry')));
    await settle(tester, rounds: 20);
    drain(tester);

    // 与单聊同一套组件：就地展开，不出现独立 BottomSheet 路由
    expect(find.byKey(const ValueKey('group-more-panel')), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('我的群聊身份'), findsOneWidget);

    // 单聊宫格的其它项目保持同一视觉位置，但群聊本轮不可用
    expect(find.text('相册'), findsOneWidget);
    expect(find.text('礼物'), findsOneWidget);
    expect(find.text('文件'), findsOneWidget);

    // 点击输入框收起面板（与单聊一致）
    await tester.tap(find.byType(TextField).first);
    await settle(tester, rounds: 12);
    drain(tester);
    expect(find.byKey(const ValueKey('group-more-panel')), findsNothing);

    // 再次展开并进入我的群聊身份
    await tester.tap(find.byKey(const ValueKey('group-extension-entry')));
    await settle(tester, rounds: 20);
    drain(tester);
    await tester.tap(find.text('我的群聊身份'));
    await settle(tester, rounds: 25);
    drain(tester);
    expect(find.byType(GroupUserProfilePage), findsOneWidget);
  });

  testWidgets('+ 展开后按钮切换为收起状态', (tester) async {
    await tester.runAsync(() async {
      await CharacterRegistryService().saveCharacters([character('q')]);
    });
    await seedGroup(tester, 'group_1');
    await pump(tester, const GroupChatPage(groupId: 'group_1'));

    expect(find.byTooltip('更多功能'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('group-extension-entry')));
    await settle(tester, rounds: 15);
    drain(tester);
    expect(find.byTooltip('收起功能栏'), findsOneWidget);
    expect(find.byKey(const ValueKey('group-more-panel')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('group-extension-entry')));
    await settle(tester, rounds: 15);
    drain(tester);
    expect(find.byKey(const ValueKey('group-more-panel')), findsNothing);
    // 面板关闭后 @ 入口仍在，mention 未受影响
    expect(find.byKey(const ValueKey('group-mention-entry')), findsOneWidget);
  });

  testWidgets('@ 功能仍可用（点击 @ 打开成员选择）', (tester) async {
    await tester.runAsync(() async {
      await CharacterRegistryService().saveCharacters([character('q')]);
    });
    await seedGroup(tester, 'group_1');
    await pump(tester, const GroupChatPage(groupId: 'group_1'));

    await tester.tap(find.byKey(const ValueKey('group-mention-entry')));
    await settle(tester, rounds: 20);
    drain(tester);
    expect(find.text('选择提醒的人'), findsOneWidget);
    expect(find.text('全体成员'), findsOneWidget);

    // 选中后应把 @全体成员 插入输入框（mention 功能未被破坏）
    await tester.tap(find.text('全体成员'));
    await settle(tester, rounds: 15);
    drain(tester);
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, contains('@全体成员'));
  });

  test('GroupChat / GroupMember schema 未新增字段', () {
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
    // 群聊身份单独落盘，不进入成员数组
    expect(
      const GroupUserProfile(groupId: 'g').toJson().keys.toSet(),
      {'groupId', 'displayName', 'avatarPath', 'selfDescription', 'updatedAt'},
    );
  });

  testWidgets('旧 group_chats.json / messages.json 仍可读取', (tester) async {
    await tester.runAsync(() async {
      final dir = Directory('${documents.path}/group_chats/legacy_group');
      await dir.create(recursive: true);
      await File('${dir.path}/messages.json').writeAsString(
        '[{"id":"old_1","groupId":"legacy_group","senderType":"character",'
        '"senderId":"q","content":"旧消息","createdAt":"2026-08-01T10:00:00.000Z"}]',
      );
      await File('${documents.path}/group_chats.json').writeAsString(
        '[{"id":"legacy_group","name":"旧群","members":[{"groupId":"legacy_group",'
        '"characterId":"q","joinedAt":"2026-08-01T10:00:00.000Z"}],'
        '"createdAt":"2026-08-01T10:00:00.000Z","lastActiveAt":"2026-08-01T10:00:00.000Z"}]',
      );
    });

    await tester.runAsync(() async {
      final group = await GroupChatStorageService().loadGroup('legacy_group');
      expect(group, isNotNull);
      expect(group!.name, '旧群');
      final messages = await GroupMessageStorageService(
        groupId: 'legacy_group',
      ).loadMessages();
      expect(messages, hasLength(1));
      expect(
        jsonDecode(File('${documents.path}/group_chats.json').readAsStringSync()),
        isA<List>(),
      );
    });
  });
}
