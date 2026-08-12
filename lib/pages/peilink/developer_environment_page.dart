import 'package:flutter/material.dart';

import '../../services/developer_environment_service.dart';
import '../../services/environment_data_service.dart';

class DeveloperEnvironmentPage extends StatefulWidget {
  const DeveloperEnvironmentPage({super.key, this.initialEnabled});

  final bool? initialEnabled;

  @override
  State<DeveloperEnvironmentPage> createState() =>
      _DeveloperEnvironmentPageState();
}

class _DeveloperEnvironmentPageState extends State<DeveloperEnvironmentPage> {
  final _environment = DeveloperEnvironmentService();
  final _data = EnvironmentDataService();
  bool _loading = true;
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    final initialEnabled = widget.initialEnabled;
    if (initialEnabled == null) {
      _load();
    } else {
      _enabled = initialEnabled;
      _loading = false;
    }
  }

  Future<void> _load() async {
    final enabled = await _environment.isEnabled();
    if (mounted) {
      setState(() {
        _enabled = enabled;
        _loading = false;
      });
    }
  }

  Future<String?> _requestKey() async {
    var enteredKey = '';
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('进入开发者沙盒'),
        content: TextField(
          obscureText: false,
          autofocus: true,
          onChanged: (value) => enteredKey = value,
          onSubmitted: (value) => Navigator.pop(context, value),
          decoration: const InputDecoration(labelText: '开发者密钥'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, enteredKey),
            child: const Text('验证'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(bool value) async {
    String? key;
    if (value) {
      key = await _requestKey();
      if (key == null || !mounted) return;
    }
    try {
      await _environment.setEnabled(value, key: key);
      if (value) await _data.initializeDeveloperSandbox();
      if (!mounted) return;
      setState(() => _enabled = value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value ? '已进入开发者沙盒，老裴数据保持原位。' : '已退出沙盒，开发者角色仅被隐藏。'),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _initialize() async {
    if (_enabled) {
      await _data.initializeDeveloperSandbox();
    } else {
      await _data.initializePlayerWorkspace();
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('基础数据环境已就绪。')));
    }
  }

  Future<void> _archivePlayerData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('隔离测试环境数据？'),
        content: const Text('用户创建角色及其角色目录会移动到环境归档中，不会删除。开发者私有角色与老裴世界数据不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('归档并清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final archive = await _data.archiveAndClearPlayerWorkspace();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已隔离到归档：${archive.path}')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('开发者与测试环境')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: SwitchListTile(
                    value: _enabled,
                    onChanged: _toggle,
                    title: const Text('开发者沙盒'),
                    subtitle: const Text('开启后显示开发者私有角色；关闭只隐藏，不删除。'),
                    secondary: const Icon(Icons.science_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(
                          Icons.playlist_add_check_circle_outlined,
                        ),
                        title: const Text('初始化基础数据'),
                        subtitle: Text(
                          _enabled ? '确认开发者沙盒与私有角色登记' : '建立空白玩家环境，不注入示例角色',
                        ),
                        onTap: _initialize,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: const Text('归档并清空玩家测试数据'),
                        subtitle: const Text('隔离用户角色目录；老裴与开发者数据保持原位'),
                        onTap: _archivePlayerData,
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    '原则：隔离，不删除。测试包首次启动为空白；开发者私有世界只在沙盒中可见。',
                    style: TextStyle(color: Colors.black54, height: 1.5),
                  ),
                ),
              ],
            ),
    );
  }
}
