import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/peilink_runtime.dart';
import 'peilink/prompt_test_mode_page.dart';
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法打开反馈问卷')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('打开失败：$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: const Text('设置'),
        centerTitle: true,
        backgroundColor: const Color(0xFFF5F5F7),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const _SectionTitle('应用设置'),
          Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  leading: const _SettingsIcon(
                    icon: Icons.hub_outlined,
                    color: Color(0xFF4D7187),
                    background: Color(0xFFE8F0F5),
                  ),
                  title: const Text(
                    '模型与 API',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('配置聊天模型、接口地址和密钥'),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.black38,
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ApiSettingsPage()),
                  ),
                ),
                if (PeiLinkRuntime.developerToolsEnabled) ...[
                  const Divider(height: 1, indent: 68),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    leading: const _SettingsIcon(
                      icon: Icons.science_outlined,
                      color: Color(0xFF7459D9),
                      background: Color(0xFFF0ECFF),
                    ),
                    title: const Text(
                      'Prompt 测试模式',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text('纯人设、极简规则与完整框架对比'),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.black38,
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PromptTestModePage(),
                      ),
                    ),
                  ),
                ],
                const Divider(height: 1, indent: 68),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  leading: const _SettingsIcon(
                    icon: Icons.feedback_outlined,
                    color: Color(0xFF4CAF50),
                    background: Color(0xFFE8F5E9),
                  ),
                  title: const Text(
                    '反馈与建议',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('前往腾讯问卷提交反馈'),
                  trailing: const Icon(
                    Icons.open_in_new_rounded,
                    color: Colors.black38,
                  ),
                  onTap: () => _openFeedbackForm(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '角色资料和记忆已归入各自的角色页面，彼此独立保存。',
              style: TextStyle(
                color: Colors.black45,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.black54,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _SettingsIcon extends StatelessWidget {
  const _SettingsIcon({
    required this.icon,
    required this.color,
    required this.background,
  });
  final IconData icon;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
    width: 38,
    height: 38,
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(icon, color: color),
  );
}
