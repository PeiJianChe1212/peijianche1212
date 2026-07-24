import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/api_settings.dart';
import '../services/api_settings_storage_service.dart';

class ApiSettingsPage extends StatefulWidget {
  const ApiSettingsPage({super.key});

  @override
  State<ApiSettingsPage> createState() => _ApiSettingsPageState();
}

class _ApiSettingsPageState extends State<ApiSettingsPage> {
  final _storage = ApiSettingsStorageService();

  final _chatApiKeyController = TextEditingController();
  final _chatBaseUrlController = TextEditingController();
  final _chatModelController = TextEditingController();

  final _multimodalApiKeyController = TextEditingController();
  final _multimodalBaseUrlController = TextEditingController();
  final _multimodalModelController = TextEditingController();

  final _imageApiKeyController = TextEditingController();
  final _imageBaseUrlController = TextEditingController();
  final _imageModelController = TextEditingController();

  String _provider = 'DeepSeek';
  bool _loading = true;
  bool _saving = false;
  String? _testingTarget;
  bool _obscureChatKey = true;
  bool _obscureMultimodalKey = true;
  bool _obscureImageKey = true;

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
    _chatApiKeyController.dispose();
    _chatBaseUrlController.dispose();
    _chatModelController.dispose();
    _multimodalApiKeyController.dispose();
    _multimodalBaseUrlController.dispose();
    _multimodalModelController.dispose();
    _imageApiKeyController.dispose();
    _imageBaseUrlController.dispose();
    _imageModelController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await _storage.loadSettings();
    if (!mounted) return;
    setState(() {
      _provider = settings.provider;
      _chatApiKeyController.text = settings.apiKey;
      _chatBaseUrlController.text = settings.baseUrl;
      _chatModelController.text = settings.model;
      _multimodalApiKeyController.text = settings.multimodalApiKey;
      _multimodalBaseUrlController.text = settings.multimodalBaseUrl;
      _multimodalModelController.text = settings.multimodalModel;
      _imageApiKeyController.text = settings.imageApiKey;
      _imageBaseUrlController.text = settings.imageBaseUrl;
      _imageModelController.text = settings.imageModel;
      _loading = false;
    });
  }

  void _applyPreset(String provider) {
    final preset = _presets[provider];
    if (preset == null) return;
    setState(() {
      _provider = provider;
      _chatBaseUrlController.text = preset.baseUrl;
      _chatModelController.text = preset.model;
    });
  }

  ApiSettings _currentSettings() {
    return ApiSettings(
      provider: _provider,
      apiKey: _chatApiKeyController.text.trim(),
      baseUrl: _chatBaseUrlController.text.trim(),
      model: _chatModelController.text.trim(),
      multimodalApiKey: _multimodalApiKeyController.text.trim(),
      multimodalBaseUrl: _multimodalBaseUrlController.text.trim(),
      multimodalModel: _multimodalModelController.text.trim(),
      imageApiKey: _imageApiKeyController.text.trim(),
      imageBaseUrl: _imageBaseUrlController.text.trim(),
      imageModel: _imageModelController.text.trim(),
    );
  }

  String? _validateUrl(String value, String label) {
    if (value.trim().isEmpty) return '请填写 $label';
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return '$label 格式不正确';
    }
    return null;
  }

  String? _validateChat(ApiSettings settings) {
    if (settings.apiKey.isEmpty) return '请填写聊天模型 API Key';
    final urlError = _validateUrl(settings.baseUrl, '聊天模型 Base URL');
    if (urlError != null) return urlError;
    if (settings.model.isEmpty) return '请填写聊天模型名称或接入点 ID';
    return null;
  }

  String? _validateMultimodal(ApiSettings settings) {
    if (settings.effectiveMultimodalApiKey.isEmpty) {
      return '请填写识图模型 API Key，或先填写聊天模型 API Key 供它共用';
    }
    final urlError = _validateUrl(
      settings.multimodalBaseUrl,
      '识图模型 Base URL',
    );
    if (urlError != null) return urlError;
    if (settings.multimodalModel.isEmpty) return '请填写识图模型接入点 ID';
    return null;
  }

  String? _validateImage(ApiSettings settings) {
    if (settings.effectiveImageApiKey.isEmpty) {
      return '请填写图片模型 API Key，或先填写聊天模型 API Key 供它共用';
    }
    final urlError = _validateUrl(settings.imageBaseUrl, '图片模型 Base URL');
    if (urlError != null) return urlError;
    if (settings.imageModel.isEmpty) return '请填写图片模型接入点 ID';
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final settings = _currentSettings();
    final error = _validateChat(settings);
    if (error != null) {
      _show(error);
      return;
    }

    setState(() => _saving = true);
    try {
      await _storage.saveSettings(settings);
      if (!mounted) return;
      _show('三个模型的配置已安全保存在本机');
    } catch (error) {
      if (!mounted) return;
      _show('保存失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testChat() async {
    final settings = _currentSettings();
    final error = _validateChat(settings);
    if (error != null) return _show(error);
    await _runTest('chat', () async {
      final data = await _postJson(
        url: settings.baseUrl,
        apiKey: settings.apiKey,
        body: {
          'model': settings.model,
          'messages': const [
            {'role': 'user', 'content': '请只回复：连接成功'},
          ],
          'stream': false,
          'max_tokens': 20,
          'temperature': 0,
        },
      );
      _readChatContent(data);
      return '聊天模型连接成功';
    });
  }

  Future<void> _testMultimodal() async {
    final settings = _currentSettings();
    final error = _validateMultimodal(settings);
    if (error != null) return _show(error);
    await _runTest('multimodal', () async {
      final data = await _postJson(
        url: settings.multimodalBaseUrl,
        apiKey: settings.effectiveMultimodalApiKey,
        body: {
          'model': settings.multimodalModel,
          'messages': const [
            {'role': 'user', 'content': '请只回复：识图模型连接成功'},
          ],
          'stream': false,
          'max_tokens': 30,
          'temperature': 0,
        },
      );
      _readChatContent(data);
      return '识图模型连接成功';
    });
  }

  Future<void> _testImage() async {
    final settings = _currentSettings();
    final error = _validateImage(settings);
    if (error != null) return _show(error);
    await _runTest('image', () async {
      final data = await _postJson(
        url: settings.imageBaseUrl,
        apiKey: settings.effectiveImageApiKey,
        timeout: const Duration(seconds: 120),
        body: {
          'model': settings.imageModel,
          'prompt': '一只放在木桌上的白色马克杯，普通手机随手拍，自然光，无文字，无水印',
          'size': '1024x1024',
          'response_format': 'url',
          'watermark': false,
        },
      );
      final list = data['data'];
      if (list is! List || list.isEmpty || list.first is! Map) {
        throw const FormatException('接口有响应，但没有返回图片地址');
      }
      final url = (list.first as Map)['url']?.toString().trim() ?? '';
      if (url.isEmpty) throw const FormatException('接口没有返回图片地址');
      return '图片模型连接成功，并已完成一张测试图';
    });
  }

  Future<void> _runTest(
    String target,
    Future<String> Function() action,
  ) async {
    if (_testingTarget != null) return;
    setState(() => _testingTarget = target);
    try {
      final message = await action();
      if (!mounted) return;
      _show(message);
    } catch (error) {
      if (!mounted) return;
      _show('连接失败：$error');
    } finally {
      if (mounted) setState(() => _testingTarget = null);
    }
  }

  Future<Map<String, dynamic>> _postJson({
    required String url,
    required String apiKey,
    required Map<String, dynamic> body,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final response = await http
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode(body),
        )
        .timeout(timeout);
    final responseText = utf8.decode(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractError(responseText, response.statusCode));
    }
    final data = jsonDecode(responseText);
    if (data is! Map<String, dynamic>) {
      throw const FormatException('接口返回格式不是 JSON 对象');
    }
    return data;
  }

  String _readChatContent(Map<String, dynamic> data) {
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw const FormatException('接口没有返回 choices');
    }
    final message = (choices.first as Map)['message'];
    if (message is! Map || message['content'] == null) {
      throw const FormatException('接口没有返回回复内容');
    }
    return message['content'].toString();
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

  void _show(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _apiKeyField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
    String? helperText,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        prefixIcon: const Icon(Icons.key_outlined),
        suffixIcon: IconButton(
          tooltip: obscure ? '显示' : '隐藏',
          onPressed: onToggle,
          icon: Icon(
            obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
        ),
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _modelCard({
    required IconData icon,
    required String title,
    required String description,
    required List<Widget> children,
    required VoidCallback? onTest,
    required bool testing,
    required String testLabel,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: TextStyle(
                color: Colors.black.withValues(alpha: 0.6),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            ...children,
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onTest,
              icon: testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering_rounded),
              label: Text(testing ? '正在测试…' : testLabel),
            ),
          ],
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
                _modelCard(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: '日常聊天模型',
                  description: '负责角色平时的文字聊天、人格和说话方式。你原来的 DeepSeek 配置仍然放在这里。',
                  testing: _testingTarget == 'chat',
                  testLabel: '测试聊天模型',
                  onTest: _testingTarget == null ? _testChat : null,
                  children: [
                    const Text(
                      '服务商',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: _presets.keys
                          .map(
                            (name) => ButtonSegment(
                              value: name,
                              label: Text(name),
                            ),
                          )
                          .toList(),
                      selected: {_provider},
                      onSelectionChanged: (values) =>
                          _applyPreset(values.first),
                      showSelectedIcon: false,
                    ),
                    const SizedBox(height: 14),
                    _apiKeyField(
                      controller: _chatApiKeyController,
                      label: '聊天模型 API Key',
                      obscure: _obscureChatKey,
                      onToggle: () =>
                          setState(() => _obscureChatKey = !_obscureChatKey),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _chatBaseUrlController,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Base URL / 完整接口地址',
                        prefixIcon: Icon(Icons.link_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _chatModelController,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: '模型名称或接入点 ID',
                        prefixIcon: Icon(Icons.memory_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _modelCard(
                  icon: Icons.visibility_outlined,
                  title: '豆包识图模型',
                  description: '负责看懂你上传的图片，也负责在生图前把生活场景整理成干净的画面描述。',
                  testing: _testingTarget == 'multimodal',
                  testLabel: '测试识图模型',
                  onTest: _testingTarget == null ? _testMultimodal : null,
                  children: [
                    _apiKeyField(
                      controller: _multimodalApiKeyController,
                      label: '识图模型 API Key（可留空）',
                      helperText: '留空时自动共用上面的聊天模型 API Key',
                      obscure: _obscureMultimodalKey,
                      onToggle: () => setState(
                        () => _obscureMultimodalKey = !_obscureMultimodalKey,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _multimodalBaseUrlController,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: '识图模型 Base URL',
                        prefixIcon: Icon(Icons.link_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _multimodalModelController,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Evolving 模型接入点 ID',
                        prefixIcon: Icon(Icons.remove_red_eye_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _modelCard(
                  icon: Icons.auto_awesome_outlined,
                  title: '豆包图片模型',
                  description: '只负责把提示词画成图片。测试时会真的生成一张马克杯图片，因此会产生一次生图调用。',
                  testing: _testingTarget == 'image',
                  testLabel: '生成测试图并验证',
                  onTest: _testingTarget == null ? _testImage : null,
                  children: [
                    _apiKeyField(
                      controller: _imageApiKeyController,
                      label: '图片模型 API Key（可留空）',
                      helperText: '留空时自动共用上面的聊天模型 API Key',
                      obscure: _obscureImageKey,
                      onToggle: () =>
                          setState(() => _obscureImageKey = !_obscureImageKey),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _imageBaseUrlController,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: '图片模型 Base URL',
                        prefixIcon: Icon(Icons.link_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _imageModelController,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: '图像创作模型接入点 ID',
                        prefixIcon: Icon(Icons.image_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '分工：日常聊天模型负责“他怎么说话”，识图模型负责“他看见了什么”，图片模型负责“把画面画出来”。三个模型不会在每条消息里一起调用。',
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.68),
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
