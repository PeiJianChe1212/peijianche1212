import 'package:flutter/material.dart';

import '../config/peilink_runtime.dart';
import '../design_system/peilink_design_system.dart';
import '../pages/core_bridge_settings_page.dart';
import '../pages/peilink/developer_environment_page.dart';
import '../pages/peilink/memory_diagnostics_page.dart';
import '../pages/peilink/physical_host_page.dart';
import '../pages/peilink/prompt_test_mode_page.dart';
import '../services/developer_environment_service.dart';

/// 仅由 `lib/main_dev.dart` 注入，user 构建不引用本文件。
List<Widget> buildDeveloperSettingsSections(BuildContext context) {
  return [
    FutureBuilder<bool>(
      future: DeveloperEnvironmentService().isEnabled(),
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();
        return Column(
          children: [
            const PeiLinkSettingsDivider(),
            PeiLinkSettingsTile(
              icon: Icons.sensors_outlined,
              title: 'PeiLink Physical',
              subtitle: '手机直连实体麦克风与喇叭',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PhysicalHostPage()),
              ),
            ),
            const PeiLinkSettingsDivider(),
            PeiLinkSettingsTile(
              icon: Icons.cable_outlined,
              title: 'Physical Core Bridge',
              subtitle: '管理仅限本机的 Physical Core 连接',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CoreBridgeSettingsPage(),
                ),
              ),
            ),
          ],
        );
      },
    ),
    if (PeiLinkRuntime.developerToolsEnabled) ...[
      const PeiLinkSettingsDivider(),
      PeiLinkSettingsTile(
        icon: Icons.construction_outlined,
        title: '开发者环境',
        subtitle: '开发者沙盒开关与测试数据初始化',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DeveloperEnvironmentPage()),
        ),
      ),
      const PeiLinkSettingsDivider(),
      PeiLinkSettingsTile(
        icon: Icons.science_outlined,
        title: 'Prompt 测试模式',
        subtitle: '纯人设、极简规则与完整框架对比',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PromptTestModePage()),
        ),
      ),
      const PeiLinkSettingsDivider(),
      PeiLinkSettingsTile(
        icon: Icons.memory_rounded,
        title: 'Memory 诊断',
        subtitle: '查看提取、检索、召回与生命周期报告',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MemoryDiagnosticsPage()),
        ),
      ),
    ],
  ];
}
