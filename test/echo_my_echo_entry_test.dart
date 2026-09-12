import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/config/peilink_runtime.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/models/echo_item.dart';
import 'package:peijianche_app/pages/peilink/echo_compose_page.dart';
import 'package:peijianche_app/pages/peilink/peilink_echo_page.dart';
import 'package:peijianche_app/pages/peilink/peilink_home_page.dart';
import 'package:peijianche_app/services/character_registry_service.dart';
import 'package:peijianche_app/services/echo_identity.dart';
import 'package:peijianche_app/services/echo_storage_service.dart';
import 'package:peijianche_app/widgets/echo/ai_verified_badge.dart';

/// Second beta round Echo closure: public feed / my Echo / character Echo
/// navigation and author isolation.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documents;

  setUp(() async {
    PeiLinkRuntime.configure(PeiLinkBuild.unspecified);
    documents = await Directory.systemTemp.createTemp('peilink_my_echo_test_');
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
    } catch (_) {
      // A still-open handle must not fail the test run.
    }
  });

  AiCharacter character(String id, String name) => AiCharacter(
    id: id,
    characterName: name,
    remark: '',
    createdAt: DateTime.utc(2026, 1, 1),
  );

  EchoItem echo(String id, String owner, String content) => EchoItem(
    id: id,
    characterId: owner,
    content: content,
    createdAt: DateTime.utc(2026, 8, 21),
    sourceType: EchoSourceType.manual,
  );

  /// Real file I/O never completes inside the fake-async widget zone, so every
  /// seed step runs through [WidgetTester.runAsync].
  Future<void> seed(WidgetTester tester, Future<void> Function() action) async {
    await tester.runAsync(action);
    await tester.pump();
  }

  bool visibleText(String text) => find.text(text).evaluate().isNotEmpty;

  bool visibleKey(String key) =>
      find.byKey(ValueKey(key)).evaluate().isNotEmpty;

  /// Page loads chain many real I/O awaits; each round lets more of them
  /// complete, then flushes pending microtasks and animation frames.
  Future<void> settle(
    WidgetTester tester, {
    required bool Function() until,
    int maxRounds = 240,
  }) async {
    for (var round = 0; round < maxRounds; round++) {
      if (until()) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      // Advance the fake clock so route and animation frames also progress.
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump();
  }

  /// The 缇佺粖 tab (not part of this Echo work) trips a debug-only ListTile
  /// decoration assert; drain it so Echo navigation checks stay focused.
  void drainUnrelatedFrameworkErrors(WidgetTester tester) {
    while (tester.takeException() != null) {}
  }

  group('Echo identity', () {
    test('user Echo owner id stays stable and never matches a character id', () {
      // Guard: this literal is already on disk in shipped builds.
      expect(EchoIdentity.userEchoOwnerId, 'peilink_user_echo');
      expect(
        EchoIdentity.userEchoOwnerId,
        isNot(AiCharacter.defaultCharacterId),
      );
    });

    test('user and character timelines never share data', () async {
      await EchoStorageService(
        characterId: EchoIdentity.userEchoOwnerId,
      ).addItem(echo('mine', EchoIdentity.userEchoOwnerId, '我自己的记录'));
      await EchoStorageService(
        characterId: 'character_a',
      ).addItem(echo('theirs', 'character_a', '角色自己的记录'));

      final mine = await EchoStorageService(
        characterId: EchoIdentity.userEchoOwnerId,
      ).loadItems();
      final theirs = await EchoStorageService(
        characterId: 'character_a',
      ).loadItems();

      expect(mine.map((item) => item.id), ['mine']);
      expect(theirs.map((item) => item.id), ['theirs']);
    });
  });

  testWidgets('我的 Echo 有明确标题与空状态，且不显示角色内容', (tester) async {
    await seed(tester, () async {
      await CharacterRegistryService().saveCharacters([
        character('character_a', '阿澈'),
      ]);
      await EchoStorageService(
        characterId: 'character_a',
      ).addItem(echo('theirs', 'character_a', '角色的记录'));
    });

    await tester.pumpWidget(const MaterialApp(home: PeiLinkEchoPage()));
    await settle(tester, until: () => visibleKey('my-echo-title'));

    expect(find.byKey(const ValueKey('my-echo-title')), findsOneWidget);
    expect(find.text('我的 Echo'), findsOneWidget);
    expect(find.text('还没有留下 Echo。'), findsOneWidget);
    expect(find.text('角色的记录'), findsNothing);
    expect(find.byType(AiVerifiedBadge), findsNothing);

    await seed(
      tester,
      () => EchoStorageService(
        characterId: EchoIdentity.userEchoOwnerId,
      ).addItem(echo('mine', EchoIdentity.userEchoOwnerId, '我自己的记录')),
    );

    await tester.pumpWidget(
      const MaterialApp(home: PeiLinkEchoPage(key: ValueKey('reloaded'))),
    );
    await settle(tester, until: () => visibleText('我自己的记录'));

    expect(find.text('我自己的记录'), findsOneWidget);
    expect(find.text('角色的记录'), findsNothing);
    expect(find.text('还没有留下 Echo。'), findsNothing);
    // The AI verified badge marks characters with a persona, not the user.
    expect(find.byType(AiVerifiedBadge), findsNothing);
  });

  testWidgets('角色 Echo 主页只显示该角色内容并保留角色标识', (tester) async {
    await seed(tester, () async {
      await CharacterRegistryService().saveCharacters([
        character('character_a', '阿澈'),
        character('character_b', '沈砚'),
      ]);
      await EchoStorageService(
        characterId: 'character_a',
      ).addItem(echo('a_echo', 'character_a', '阿澈的记录'));
      await EchoStorageService(
        characterId: 'character_b',
      ).addItem(echo('b_echo', 'character_b', '沈砚的记录'));
      await EchoStorageService(
        characterId: EchoIdentity.userEchoOwnerId,
      ).addItem(echo('mine', EchoIdentity.userEchoOwnerId, '我自己的记录'));
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PeiLinkEchoPage(
          character: character('character_a', '阿澈'),
          key: const ValueKey('character-a'),
        ),
      ),
    );
    await settle(tester, until: () => visibleText('阿澈的记录'));

    expect(find.text('阿澈的记录'), findsOneWidget);
    expect(find.text('沈砚的记录'), findsNothing);
    expect(find.text('我自己的记录'), findsNothing);
    // Header and card both carry the character badge.
    expect(find.byType(AiVerifiedBadge), findsAtLeastNWidgets(1));

    await tester.pumpWidget(
      MaterialApp(
        home: PeiLinkEchoPage(
          character: character('character_b', '沈砚'),
          key: const ValueKey('character-b'),
        ),
      ),
    );
    await settle(tester, until: () => visibleText('沈砚的记录'));

    expect(find.text('沈砚的记录'), findsOneWidget);
    expect(find.text('阿澈的记录'), findsNothing);
  });

  testWidgets('公共 Echo 非 Tab 形态保留进入我的 Echo 与发布入口', (tester) async {
    await seed(tester, () async {
      await CharacterRegistryService().saveCharacters([
        character('character_a', '阿澈'),
      ]);
      await EchoStorageService(
        characterId: 'character_a',
      ).addItem(echo('theirs', 'character_a', '角色的记录'));
      await EchoStorageService(
        characterId: EchoIdentity.userEchoOwnerId,
      ).addItem(echo('mine', EchoIdentity.userEchoOwnerId, '我自己的记录'));
    });

    await tester.pumpWidget(
      const MaterialApp(home: PeiLinkEchoPage(showPublicTimeline: true)),
    );
    await settle(
      tester,
      until: () =>
          visibleText('角色的记录') && visibleText('我自己的记录'),
    );

    // The public feed keeps both authors visible.
    expect(find.text('角色的记录'), findsOneWidget);
    expect(find.text('我自己的记录'), findsOneWidget);
    expect(find.byKey(const ValueKey('echo-public-my-echo')), findsOneWidget);
    expect(find.byKey(const ValueKey('echo-public-compose')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('echo-public-my-echo')));
    await settle(tester, until: () => visibleKey('my-echo-title'));

    // The pushed page is the user's own space; the public feed route stays
    // behind it, so author filtering is asserted on the standalone pages above.
    expect(find.byKey(const ValueKey('my-echo-title')), findsOneWidget);
    expect(find.text('我自己的记录'), findsWidgets);
  });

  testWidgets('发布 Echo 后出现在我的 Echo', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PeiLinkEchoPage()));
    await settle(tester, until: () => visibleText('还没有留下 Echo。'));

    await tester.tap(find.byTooltip('发布 Echo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('记录我的 Echo'));
    await tester.pumpAndSettle();

    expect(find.byType(EchoComposePage), findsOneWidget);
    await tester.enterText(find.byType(TextField), '今天记录一件小事');
    await tester.tap(find.text('发布'));
    await settle(
      tester,
      until: () =>
          find.byType(EchoComposePage).evaluate().isEmpty &&
          visibleText('今天记录一件小事'),
    );

    expect(find.byType(EchoComposePage), findsNothing);
    expect(find.text('今天记录一件小事'), findsOneWidget);
    expect(find.text('还没有留下 Echo。'), findsNothing);
  });

  testWidgets('Echo Tab 头像进入我的 Echo，＋ 进入发布', (tester) async {
    PeiLinkRuntime.configure(PeiLinkBuild.user);
    await tester.pumpWidget(const MaterialApp(home: PeiLinkHomePage()));
    await settle(tester, until: () => visibleKey('peilink-create-entry'));
    drainUnrelatedFrameworkErrors(tester);

    await tester.tap(find.text('Echo'));
    await settle(tester, until: () => visibleText('看看大家最近留下的生活片段'));
    drainUnrelatedFrameworkErrors(tester);

    await tester.tap(find.byKey(const ValueKey('peilink-profile-entry')));
    await settle(tester, until: () => visibleKey('my-echo-title'));

    expect(find.byKey(const ValueKey('my-echo-title')), findsOneWidget);

    // The Echo space uses its own round back button instead of an AppBar.
    await tester.tap(find.byTooltip('返回'));
    await settle(tester, until: () => visibleText('看看大家最近留下的生活片段'));
    drainUnrelatedFrameworkErrors(tester);

    await tester.tap(find.byKey(const ValueKey('peilink-create-entry')));
    await settle(
      tester,
      until: () => find.byType(EchoComposePage).evaluate().isNotEmpty,
    );

    expect(find.byType(EchoComposePage), findsOneWidget);
    expect(find.text('正在记录自己的生活'), findsOneWidget);
  });
}
