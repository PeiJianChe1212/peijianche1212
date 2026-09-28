import 'package:flutter/material.dart';

import '../config/peilink_settings_sections_registry.dart';
import '../design_system/peilink_design_system.dart';
import '../services/feedback_form_launcher.dart';
import 'api_settings_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PeiLinkPageScaffold(
      appBar: const PeiLinkAppBar(
        title: '设置',
        subtitle: '管理 PeiLink 的连接与帮助选项',
        mode: PeiLinkAppBarMode.glass,
      ),
      body: PeiLinkPageList(
        children: [
          const PeiLinkSectionHeader(title: 'AI 与模型'),
          PeiLinkSurface(
            child: Column(
              children: [
                PeiLinkSettingsTile(
                  icon: Icons.hub_outlined,
                  title: '模型与 API',
                  subtitle: '配置聊天模型、接口地址和密钥',
                  iconColor: const Color(0xFF557C96),
                  iconBackground: const Color(0xFFE8F0F5),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ApiSettingsPage()),
                  ),
                ),
                ...PeiLinkSettingsSectionsRegistry.buildSections(context),
              ],
            ),
          ),
          const SizedBox(height: PeiLinkSpacing.section),
          const PeiLinkSectionHeader(title: '支持与建议'),
          PeiLinkSurface(
            child: PeiLinkSettingsTile(
              icon: Icons.feedback_outlined,
              title: '反馈与建议',
              subtitle: '前往飞书表单提交反馈',
              showArrow: false,
              iconColor: PeiLinkColors.success,
              iconBackground: const Color(0xFFE8F5E9),
              trailing: const Icon(
                Icons.open_in_new_rounded,
                color: PeiLinkColors.textTertiary,
                size: 20,
              ),
              onTap: () => FeedbackFormLauncher.open(context),
            ),
          ),
          const SizedBox(height: PeiLinkSpacing.lg),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: PeiLinkSpacing.xs),
            child: Text(
              '角色资料和记忆已归入各自的角色页面，彼此独立保存。',
              style: PeiLinkTypography.secondary,
            ),
          ),
        ],
      ),
    );
  }
}
