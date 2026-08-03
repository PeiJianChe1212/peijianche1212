import 'package:flutter/material.dart';

import '../services/auto_echo_service.dart';
import 'api_settings_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _testingEcho = false;

  Future<void> _generateTestEcho() async {
    if (_testingEcho) return;
    setState(() => _testingEcho = true);
    try {
      final item = await AutoEchoService().generateTestEcho();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('测试 Echo 已生成：${item.content}')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('生成测试 Echo 失败：$error')));
    } finally {
      if (mounted) setState(() => _testingEcho = false);
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
                const Divider(height: 1, indent: 70),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  leading: const _SettingsIcon(
                    icon: Icons.auto_awesome_rounded,
                    color: Color(0xFF9A6884),
                    background: Color(0xFFF5EAF1),
                  ),
                  title: const Text(
                    'Echo 测试',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('立即为当前角色生成一条测试生活动态'),
                  trailing: _testingEcho
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          Icons.play_circle_outline_rounded,
                          color: Colors.black38,
                        ),
                  onTap: _testingEcho ? null : _generateTestEcho,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '角色的人设、相处模式、主动联系和记忆，已经归入各自的角色设置。',
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
