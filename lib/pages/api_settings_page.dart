import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/ai_capability.dart';
import '../models/api_settings.dart';
import '../services/api_settings_storage_service.dart';

class ApiSettingsPage extends StatefulWidget {
  const ApiSettingsPage({super.key});

  @override
  State<ApiSettingsPage> createState() => _ApiSettingsPageState();
}

class _ApiSettingsPageState extends State<ApiSettingsPage> {
  final _storage = ApiSettingsStorageService();
  final _apiKeyController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _modelController = TextEditingController();

  String _provider = 'DeepSeek';
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  bool _obscureKey = true;

  static const Map<String, ApiSettings> _presets = {
    'DeepSeek': ApiSettings(
      provider: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1/chat/completions',
      model: 'deepseek-chat',
    ),
    '豆包 / 火山方舟': ApiSettings(
      provider: '豆包 / 火山方舟',
      baseUrl: 'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
      model: '',
    ),
    '自定义': ApiSettings(provider: '自定义', baseUrl: '', model: ''),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await _storage.loadSettings();
    if (!mounted) return;
    setState(() {
      _provider = settings.provider;
      _apiKeyController.text = settings.apiKey;
      _baseUrlController.text = settings.baseUrl;
      _modelController.text = settings.model;
      _loading = false;
    });
  }

  void _applyPreset(String provider) {
    final preset = _presets[provider];
    if (preset == null) return;
    setState(() {
      _provider = provider;
      _baseUrlController.text = preset.baseUrl;
      _modelController.text = preset.model;
    });
  }

  ApiSettings _currentSettings() {
    return ApiSettings(
      provider: _provider,
      apiKey: _apiKeyController.text.trim(),
      baseUrl: _baseUrlController.text.trim(),
      model: _modelController.text.trim(),
    );
  }

  String? _validate(ApiSettings settings) {
    if (settings.apiKey.isEmpty) return '请填写 API Key';
    if (settings.baseUrl.isEmpty) return '请填写 Base URL';
    final uri = Uri.tryParse(settings.baseUrl);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return 'Base URL 格式不正确';
    }
    if (settings.model.isEmpty) return '请填写模型名称或接入点 ID';
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final settings = _currentSettings();
    final error = _validate(settings);
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    setState(() => _saving = true);
    try {
      await _storage.saveSettings(settings);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('模型与 API 设置已安全保存在本机')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：$error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testConnection() async {
    if (_testing) return;
    final settings = _currentSettings();
    final error = _validate(settings);
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    setState(() => _testing = true);
    try {
      final response = await http
          .post(
            Uri.parse(settings.baseUrl),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Authorization': 'Bearer ${settings.apiKey}',
            },
            body: jsonEncode({
              'model': settings.model,
              'messages': const [
                {'role': 'user', 'content': '请只回复：连接成功'},
              ],
              'stream': false,
              'max_tokens': 20,
              'temperature': 0,
            }),
          )
          .timeout(const Duration(seconds: 30));

      final body = utf8.decode(response.bodyBytes);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_extractError(body, response.statusCode));
      }

      final data = jsonDecode(body);
      if (data is! Map || data['choices'] is! List) {
        throw const FormatException('接口有响应，但返回格式不是兼容的聊天格式');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('连接成功，可以开始聊天了')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('连接失败：$error')));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  String _extractError(String body, int statusCode) {
    try {
      final data = jsonDecode(body);
      if (data is Map && data['error'] is Map) {
        final message = data['error']['message'];
        if (message != null) return 'API $statusCode：$message';
      }
    } catch (_) {}
    return 'API $statusCode：$body';
  }


  Widget _buildCapabilityTile({
    required AiCapability capability,
    required IconData icon,
    required String status,
    required bool active,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        icon,
        color: active ? Theme.of(context).colorScheme.primary : Colors.black45,
      ),
      title: Text(capability.label),
      subtitle: Text(capability.description),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? Theme.of(context).colorScheme.primaryContainer
              : const Color(0xFFF1F1F1),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          status,
          style: TextStyle(
            fontSize: 12,
            color: active
                ? Theme.of(context).colorScheme.onPrimaryContainer
                : Colors.black54,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('模型与 API'),
        actions: [
          TextButton(
            onPressed: _loading || _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
              children: [
                const Text(
                  '服务商',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: _presets.keys
                      .map(
                        (name) => ButtonSegment(value: name, label: Text(name)),
                      )
                      .toList(),
                  selected: {_provider},
                  onSelectionChanged: (values) => _applyPreset(values.first),
                  showSelectedIcon: false,
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _apiKeyController,
                  obscureText: _obscureKey,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    hintText: 'sk-…',
                    prefixIcon: const Icon(Icons.key_outlined),
                    suffixIcon: IconButton(
                      tooltip: _obscureKey ? '显示' : '隐藏',
                      onPressed: () =>
                          setState(() => _obscureKey = !_obscureKey),
                      icon: Icon(
                        _obscureKey
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _baseUrlController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Base URL / 完整接口地址',
                    prefixIcon: Icon(Icons.link_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _modelController,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: _provider == '豆包 / 火山方舟'
                        ? '模型名称或推理接入点 ID'
                        : '模型名称',
                    prefixIcon: const Icon(Icons.memory_outlined),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '模型能力',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: Column(
                      children: [
                        _buildCapabilityTile(
                          capability: AiCapability.chat,
                          icon: Icons.chat_bubble_outline_rounded,
                          status: '当前使用',
                          active: true,
                        ),
                        const Divider(height: 1),
                        _buildCapabilityTile(
                          capability: AiCapability.imageGeneration,
                          icon: Icons.image_outlined,
                          status: '框架已就绪',
                          active: false,
                        ),
                        const Divider(height: 1),
                        _buildCapabilityTile(
                          capability: AiCapability.textToSpeech,
                          icon: Icons.graphic_eq_rounded,
                          status: '框架已就绪',
                          active: false,
                        ),
                        const Divider(height: 1),
                        _buildCapabilityTile(
                          capability: AiCapability.speechToText,
                          icon: Icons.mic_none_rounded,
                          status: '框架已就绪',
                          active: false,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _testing ? null : _testConnection,
                  icon: _testing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering_rounded),
                  label: Text(_testing ? '正在测试…' : '测试连接'),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.shield_outlined),
                            SizedBox(width: 8),
                            Text(
                              '本机安全存储',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'API Key 不再写进源码，而是保存在系统加密存储中。更换服务商后，聊天会从下一条消息开始使用新配置。',
                          style: TextStyle(
                            color: Colors.black.withValues(alpha: 0.62),
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_provider == '豆包 / 火山方舟') ...[
                  const SizedBox(height: 12),
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        '豆包通常需要在火山方舟控制台创建推理接入点。请把控制台提供的模型名称或接入点 ID 填在上方。',
                        style: TextStyle(height: 1.45),
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
