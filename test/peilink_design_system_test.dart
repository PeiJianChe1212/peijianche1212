import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/config/peilink_runtime.dart';
import 'package:peijianche_app/design_system/peilink_design_system.dart';
import 'package:peijianche_app/pages/settings_page.dart';
import 'package:peijianche_app/config/peilink_settings_sections_registry.dart';
import 'package:peijianche_app/dev_only/developer_settings_sections.dart';

void main() {
  tearDown(() => PeiLinkRuntime.configure(PeiLinkBuild.unspecified));

  testWidgets('Design System 基础组件可共同构建', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: PeiLinkPageScaffold(
          appBar: PeiLinkAppBar(
            title: '很长的二级页面标题也应该安全显示',
            subtitle: '副标题',
            actions: [
              PeiLinkAppBar.addAction(onPressed: () {}),
              PeiLinkAppBar.moreAction(onPressed: () {}),
            ],
          ),
          body: ListView(
            children: [
              const PeiLinkSurface(child: Text('Surface')),
              PeiLinkPrimaryButton(label: 'Primary', onPressed: () {}),
              PeiLinkSecondaryButton(label: 'Secondary', onPressed: () {}),
              const PeiLinkTextButton(label: 'Disabled'),
              PeiLinkDangerButton(label: 'Danger', onPressed: () {}),
              PeiLinkTextField(
                controller: controller,
                label: '名称',
                hint: '请输入',
              ),
              PeiLinkSettingsTile(
                icon: Icons.settings,
                title: '设置项',
                subtitle: '很长的设置项说明用于确认布局可以自然换行',
                value: '当前值',
                onTap: () {},
              ),
              PeiLinkSettingsTile(
                icon: Icons.toggle_on,
                title: '开关',
                switchValue: true,
                onSwitchChanged: (_) {},
              ),
              const PeiLinkEmptyState(title: '没有内容', compact: true),
              const PeiLinkLoadingState(compact: true),
              PeiLinkErrorState(title: '加载失败', onRetry: () {}, compact: true),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Surface'), findsOneWidget);
    expect(find.text('Primary'), findsOneWidget);
    expect(find.text('没有内容'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Confirm Dialog 支持普通与危险确认', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => PeiLinkConfirmDialog.show(
              context,
              title: '删除内容？',
              description: '此操作需要确认。',
              danger: true,
              irreversibleWarning: '删除后无法恢复。',
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('删除内容？'), findsOneWidget);
    expect(find.text('删除后无法恢复。'), findsOneWidget);
    expect(find.byType(PeiLinkDangerButton), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('删除内容？'), findsNothing);
  });

  for (final size in <Size>[
    const Size(320, 640),
    const Size(360, 800),
    const Size(411, 891),
  ]) {
    testWidgets(
      'Settings 在 ${size.width.toInt()}×${size.height.toInt()} 无溢出且入口完整',
      (tester) async {
        PeiLinkRuntime.configure(PeiLinkBuild.user);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
        await tester.pump();

        expect(find.text('设置'), findsOneWidget);
        expect(find.text('模型与 API'), findsOneWidget);
        expect(find.text('反馈与建议'), findsOneWidget);
        expect(find.text('Prompt 测试模式'), findsNothing);
        expect(find.byType(PeiLinkPageScaffold), findsOneWidget);
        expect(find.byType(PeiLinkSurface), findsNWidgets(2));
        expect(find.byType(Scrollable), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Settings 保留返回和 dev Prompt 入口', (tester) async {
    PeiLinkRuntime.configure(PeiLinkBuild.dev);
    PeiLinkSettingsSectionsRegistry.installDeveloperSections(
      buildDeveloperSettingsSections,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            ),
            child: const Text('进入设置'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('进入设置'));
    await tester.pumpAndSettle();

    expect(find.text('Prompt 测试模式'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('进入设置'), findsOneWidget);
  });
}
