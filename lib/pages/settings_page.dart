import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/peilink_settings_sections_registry.dart';
import '../design_system/peilink_design_system.dart';
import 'api_settings_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const MethodChannel _channel = MethodChannel('peilink/external_url');
  static const String _feedbackFormUrl = 'https://wj.qq.com/s2/27544350/qi8v/';

  Future<void> _openFeedbackForm(BuildContext context) async {
    try {
      final opened = await _channel.invokeMethod<bool>(
        'open',
        _feedbackFormUrl,
      );
      if (opened != true && context.mounted) {
        PeiLinkFeedback.show(
          context,
          '无法打开反馈问卷',
          type: PeiLinkFeedbackType.warning,
        );
      }
    } catch (e) {
      if (context.mounted) {
        PeiLinkFeedback.show(
          context,
          '打开失败：$e',
          type: PeiLinkFeedbackType.error,
        );
      }
    }
  }

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
              subtitle: '前往腾讯问卷提交反馈',
              showArrow: false,
              iconColor: PeiLinkColors.success,
              iconBackground: const Color(0xFFE8F5E9),
              trailing: const Icon(
                Icons.open_in_new_rounded,
                color: PeiLinkColors.textTertiary,
                size: 20,
              ),
              onTap: () => _openFeedbackForm(context),
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
