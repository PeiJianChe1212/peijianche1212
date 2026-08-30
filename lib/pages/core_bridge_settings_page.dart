import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design_system/peilink_design_system.dart';
import '../services/core_bridge_config_service.dart';
import '../services/core_bridge_runtime.dart';

class CoreBridgeSettingsPage extends StatefulWidget {
  const CoreBridgeSettingsPage({super.key});

  @override
  State<CoreBridgeSettingsPage> createState() =>
      _CoreBridgeSettingsPageState();
}

class _CoreBridgeSettingsPageState extends State<CoreBridgeSettingsPage> {
  final _runtime = CoreBridgeRuntime.instance;
  bool _enabled = false;
  bool _busy = true;
  bool _showToken = false;
  String _token = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await _runtime.loadConfig();
    if (!mounted) return;
    setState(() {
      _enabled = config.enabled && _runtime.isRunning;
      _token = config.token;
      _busy = false;
    });
  }

  Future<void> _setEnabled(bool value) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (value) {
        _token = await _runtime.enable();
      } else {
        await _runtime.disable();
      }
      if (!mounted) return;
      setState(() => _enabled = value && _runtime.isRunning);
    } catch (_) {
      if (mounted) {
        PeiLinkFeedback.show(
          context,
          'Bridge 启动失败，请确认本机端口 ${CoreBridgeConfigService.port} 未被占用。',
          type: PeiLinkFeedbackType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyToken() async {
    if (_token.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _token));
    if (mounted) PeiLinkFeedback.show(context, 'Bridge Token 已复制');
  }

  Future<void> _rotateToken() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      _token = await _runtime.rotateToken();
      if (!mounted) return;
      setState(() => _showToken = true);
      PeiLinkFeedback.show(context, 'Bridge Token 已更新，Physical 端需同步更新');
    } catch (_) {
      if (mounted) {
        PeiLinkFeedback.show(
          context,
          'Token 更新失败',
          type: PeiLinkFeedbackType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleToken = _showToken ? _token : '••••••••••••••••';
    return PeiLinkPageScaffold(
      appBar: const PeiLinkAppBar(
        title: 'Physical Core Bridge',
        subtitle: '仅供本机 Physical 主机连接',
        mode: PeiLinkAppBarMode.glass,
      ),
      body: PeiLinkPageList(
        children: [
          const PeiLinkSectionHeader(title: '本机连接'),
          PeiLinkSurface(
            child: Column(
              children: [
                SwitchListTile(
                  value: _enabled,
                  onChanged: _busy ? null : _setEnabled,
                  title: const Text('启用 Core Bridge'),
                  subtitle: Text(
                    _enabled
                        ? '正在监听 127.0.0.1:${CoreBridgeConfigService.port}'
                        : '默认关闭，不监听任何端口',
                  ),
                ),
                if (_enabled) ...[
                  const PeiLinkSettingsDivider(),
                  ListTile(
                    title: const Text('Bridge Token'),
                    subtitle: SelectableText(visibleToken),
                    trailing: IconButton(
                      tooltip: _showToken ? '隐藏' : '显示',
                      onPressed: () => setState(() => _showToken = !_showToken),
                      icon: Icon(
                        _showToken
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _copyToken,
                            icon: const Icon(Icons.copy_outlined),
                            label: const Text('复制 Token'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _rotateToken,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('更新 Token'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: PeiLinkSpacing.section),
          const PeiLinkSurface(
            child: Padding(
              padding: EdgeInsets.all(PeiLinkSpacing.md),
              child: Text(
                'Bridge 只接受本机 127.0.0.1 请求。它会读取角色现有最近聊天作为上下文，'
                '但不会把 Physical 本轮消息或回复写入正式聊天历史。模型 API Key 始终由 PeiLink 管理。',
                style: PeiLinkTypography.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
