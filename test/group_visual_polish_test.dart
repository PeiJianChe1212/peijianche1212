import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/config/peilink_runtime.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/models/group_chat.dart';
import 'package:peijianche_app/models/group_member.dart';
import 'package:peijianche_app/models/group_message.dart';
import 'package:peijianche_app/models/group_user_profile.dart';
import 'package:peijianche_app/pages/peilink/group_chat_page.dart';
import 'package:peijianche_app/pages/peilink/group_chat_settings_page.dart';
import 'package:peijianche_app/pages/peilink/group_user_profile_page.dart';
import 'package:peijianche_app/services/character_registry_service.dart';
import 'package:peijianche_app/services/group_chat_storage_service.dart';
import 'package:peijianche_app/services/group_message_storage_service.dart';
import 'package:peijianche_app/services/group_user_profile_storage_service.dart';
import 'package:peijianche_app/services/peilink_appearance_service.dart';
import 'package:peijianche_app/theme/app_theme_background.dart';
import 'package:peijianche_app/theme/theme_background_surface.dart';
import 'package:peijianche_app/widgets/chat/chat_more_panel.dart';
import 'package:peijianche_app/widgets/group/group_visuals.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late PeiLinkAppearanceController appearance;
  final captureKey = GlobalKey();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final qa = Platform.environment['PEILINK_VISUAL_QA'] == '1';
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('group_visual_');
    PeiLinkRuntime.configure(PeiLinkBuild.unspecified);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => dir.path);
    appearance = PeiLinkAppearanceController.testing(
      fileProvider: () async => File('${dir.path}/appearance.json'),
    );
  });
  tearDown(() async {
    appearance.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    PeiLinkRuntime.configure(PeiLinkBuild.unspecified);
    await dir.delete(recursive: true);
  });
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(tester.takeException(), isNull);
  }

  Future<void> seed(WidgetTester tester) async => tester.runAsync(() async {
    await CharacterRegistryService().saveCharacters([
      for (final id in ['a', 'b', 'c'])
        AiCharacter(
          id: id,
          characterName: '成员$id · 很长的角色昵称测试',
          remark: '',
          createdAt: DateTime(2026),
        ),
    ]);
    await GroupChatStorageService().upsertGroup(
      GroupChat(
        id: 'visual',
        name: '午后的小小会客厅 · 很长的群名称',
        createdAt: DateTime(2026),
        lastActiveAt: DateTime(2026),
        members: [
          for (final id in ['a', 'b', 'c'])
            GroupMember(
              groupId: 'visual',
              characterId: id,
              joinedAt: DateTime(2026),
            ),
        ],
      ),
    );
    await GroupUserProfileStorageService(groupId: 'visual').save(
      const GroupUserProfile(
        groupId: 'visual',
        displayName: '念念',
        selfDescription: '一起聊天的老朋友',
      ),
    );
    await GroupMessageStorageService(groupId: 'visual').saveMessages([
      GroupMessage(
        id: 'm1',
        groupId: 'visual',
        senderType: GroupSenderType.character,
        senderId: 'a',
        content: '今天过得怎么样？一起坐下来聊聊吧。',
        createdAt: DateTime(2026, 9, 10, 15),
      ),
      GroupMessage(
        id: 'm2',
        groupId: 'visual',
        senderType: GroupSenderType.user,
        senderId: 'user',
        content: '还不错呀～😊',
        createdAt: DateTime(2026, 9, 10, 15, 1),
      ),
    ]);
  });
  Future<void> pump(
    WidgetTester tester,
    Widget page, {
    double scale = 1.3,
  }) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    if (qa) {
      await tester.runAsync(() async {
        final font = FontLoader('sans-serif');
        font.addFont(
          Future.value(
            ByteData.sublistView(
              await File('C:/Windows/Fonts/msyh.ttc').readAsBytes(),
            ),
          ),
        );
        await font.load();
        final icons = FontLoader('MaterialIcons');
        icons.addFont(
          Future.value(
            ByteData.sublistView(
              await File(
                'G:/dev/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
              ).readAsBytes(),
            ),
          ),
        );
        await icons.load();
      });
    }
    await tester.pumpWidget(
      PeiLinkAppearanceScope(
        controller: appearance,
        child: RepaintBoundary(
          key: captureKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              fontFamily: 'sans-serif',
              colorScheme: ColorScheme.fromSeed(seedColor: GroupVisuals.accent),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: page,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!qa) return;
    final old = debugDisableShadows;
    debugDisableShadows = false;
    await tester.pump();
    await tester.runAsync(() async {
      final image =
          await (captureKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        'build/visual_polish_$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    debugDisableShadows = old;
  }

  test(
    'old backgrounds preserved and twelve new choices restore by ID',
    () async {
      expect(AppThemeBackground.builtInPack.take(6).map((b) => b.id), [
        'cat_paw_blush',
        'star_butterfly_blue',
        'cream_bear',
        'mist_star',
        'lavender_flower',
        'soft_cloud_blue',
      ]);
      expect(AppThemeBackground.legacyAtmospherePack.length, 6);
      final added = AppThemeBackground.builtInPack.skip(6).toList();
      expect(added.length, 12);
      expect(added.where((b) => b.imagePath != null), isEmpty);
      for (final b in added) {
        await appearance.setBackground(b);
        final restored = PeiLinkAppearanceController.testing(
          fileProvider: () async => File('${dir.path}/appearance.json'),
        );
        await restored.load();
        expect(restored.background.id, b.id);
        restored.dispose();
      }
    },
  );
  testWidgets(
    'member management keeps self locked and requires two AI members',
    (tester) async {
      await seed(tester);
      await pump(tester, const GroupChatSettingsPage(groupId: 'visual'));
      await capture(tester, 'settings');
      await tester.tap(find.byKey(const ValueKey('group-member-manage')));
      await settle(tester);
      expect(find.byType(CheckboxListTile), findsNothing);
      final locked = tester
          .widgetList<GroupMemberChoice>(find.byType(GroupMemberChoice))
          .singleWhere((w) => w.locked);
      expect(locked.onTap, isNull);
      expect(locked.selected, isTrue);
      await capture(tester, 'members');
      await tester.tap(find.byKey(const ValueKey('manage-member-a')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('manage-member-b')));
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '完成'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('manage-member-b')));
      await tester.pump();
      await tester.tap(find.text('完成'));
      await settle(tester);
      await tester.runAsync(() async {
        expect(
          (await GroupChatStorageService().loadGroup(
            'visual',
          ))!.memberCharacterIds,
          containsAll(['b', 'c']),
        );
      });
      expect(find.text('群成员已更新'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'dark group screen and inline panel remain usable with keyboard',
    (tester) async {
      await seed(tester);
      await tester.runAsync(
        () => appearance.setBackground(AppThemeBackground.midnightSlate),
      );
      await pump(tester, const GroupChatPage(groupId: 'visual'));
      await capture(tester, 'chat');
      await tester.tap(find.byKey(const ValueKey('group-extension-entry')));
      await settle(tester);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(ChatMorePanel), findsOneWidget);
      await capture(tester, 'panel');
      final panel = tester.widget<ChatMorePanel>(find.byType(ChatMorePanel));
      expect(panel.highlightPersona, isTrue);
      expect(
        panel.disabledLabels,
        containsAll(['相册', '红包', '让 Ta 换头像', '礼物', '文件', '虚拟定位', '音乐', '语音通话']),
      );
      await tester.tap(find.byType(TextField));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await settle(tester);
      expect(find.byType(ChatMorePanel), findsNothing);
      expect(
        tester.getBottomRight(find.byType(TextField)).dy,
        lessThanOrEqualTo(500),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'group identity page preserves fields at large text and keyboard',
    (tester) async {
      await seed(tester);
      await pump(
        tester,
        const GroupUserProfilePage(groupId: 'visual', groupName: '午后的小小会客厅'),
      );
      await capture(tester, 'identity');
      expect(find.byKey(const ValueKey('group-identity-name')), findsOneWidget);
      final field = find.byKey(const ValueKey('group-identity-description'));
      await tester.tap(field);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await settle(tester);
      await tester.ensureVisible(field);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('new background thumbnails use the real background surface', (
    tester,
  ) async {
    await pump(
      tester,
      Scaffold(
        body: GridView.count(
          crossAxisCount: 3,
          childAspectRatio: .58,
          padding: const EdgeInsets.all(12),
          children: [
            for (final b in AppThemeBackground.builtInPack.skip(6))
              Padding(
                padding: const EdgeInsets.all(4),
                child: Column(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: ThemeBackgroundSurface(background: b),
                      ),
                    ),
                    Text(b.name, style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
          ],
        ),
      ),
      scale: 1,
    );
    await capture(tester, 'backgrounds');
    expect(tester.takeException(), isNull);
  });
}
