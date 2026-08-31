import 'package:flutter/material.dart';

import '../../design_system/peilink_design_system.dart';
import '../../models/ai_character.dart';
import '../../physical/physical_host_settings.dart';
import '../../physical/physical_host_settings_storage.dart';
import '../../physical/physical_session_controller.dart';
import '../../services/character_registry_service.dart';
import '../../services/developer_environment_service.dart';

class PhysicalHostPage extends StatelessWidget {
  const PhysicalHostPage({super.key});

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: DeveloperEnvironmentService().isEnabled(),
    builder: (context, snapshot) => snapshot.data == true
        ? const _PhysicalHostContent()
        : const Scaffold(body: SizedBox.shrink()),
  );
}

class _PhysicalHostContent extends StatefulWidget {
  const _PhysicalHostContent();

  @override
  State<_PhysicalHostContent> createState() => _PhysicalHostPageState();
}

class _PhysicalHostPageState extends State<_PhysicalHostContent> {
  static const _stageEText = '你这是在给录音设备报数，还是在测试我听力？';
  final _storage = PhysicalHostSettingsStorage();
  final _controller = PhysicalSessionController();
  final _host = TextEditingController();
  final _requestKey = TextEditingController();
  final _apiKey = TextEditingController();
  final _boostingId = TextEditingController();
  List<AiCharacter> _characters = const [];
  String _characterId = '';
  double _gain = 0.18;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_refresh);
    _load();
  }

  Future<void> _load() async {
    final settings = await _storage.load();
    final characters = await CharacterRegistryService().loadCharacters();
    if (!mounted) return;
    _host.text = settings.esp32Host;
    _requestKey.text = settings.requestKey;
    _apiKey.text = settings.volcengineApiKey;
    _boostingId.text = settings.boostingTableId;
    _characters = characters;
    _characterId = characters.any((item) => item.id == settings.characterId)
        ? settings.characterId
        : (characters.isEmpty ? '' : characters.first.id);
    _controller.selectCharacter(_characterId);
    _gain = settings.playbackGain.clamp(0.01, 0.25);
    setState(() => _loading = false);
  }

  PhysicalHostSettings get _settings => PhysicalHostSettings(
    esp32Host: _host.text,
    requestKey: _requestKey.text,
    volcengineApiKey: _apiKey.text,
    boostingTableId: _boostingId.text,
    characterId: _characterId,
    playbackGain: _gain,
  );

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _storage.save(_settings);
      if (mounted) PeiLinkFeedback.show(context, 'Physical 配置已安全保存');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    _controller.dispose();
    _host.dispose();
    _requestKey.dispose();
    _apiKey.dispose();
    _boostingId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PeiLinkPageScaffold(
      appBar: const PeiLinkAppBar(
        title: 'PeiLink Physical',
        subtitle: '手机直连实体终端 · 人工单轮 · 严格半双工',
        mode: PeiLinkAppBarMode.glass,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _controller.canReplyOnly
            ? () => _controller.replyOnly(_settings)
            : null,
        icon: const Icon(Icons.psychology_alt_outlined),
        label: const Text('仅生成 AI 回复（Stage D）'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : PeiLinkPageList(
              children: [
                const PeiLinkSectionHeader(title: '本机私密配置'),
                PeiLinkSurface(
                  child: Padding(
                    padding: const EdgeInsets.all(PeiLinkSpacing.md),
                    child: Column(
                      children: [
                        TextField(
                          controller: _host,
                          enabled: !_controller.isBusy,
                          decoration: const InputDecoration(
                            labelText: 'ESP32 局域网地址',
                            hintText: '192.168.x.x',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _requestKey,
                          enabled: !_controller.isBusy,
                          obscureText: true,
                          enableSuggestions: false,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'ESP32 请求密钥',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _apiKey,
                          enabled: !_controller.isBusy,
                          obscureText: true,
                          enableSuggestions: false,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: '豆包语音 API Key',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _boostingId,
                          enabled: !_controller.isBusy,
                          decoration: const InputDecoration(
                            labelText: 'ASR 热词表 ID（可选）',
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _characterId.isEmpty
                              ? null
                              : _characterId,
                          decoration: const InputDecoration(
                            labelText: 'Physical 角色',
                          ),
                          items: _characters
                              .map(
                                (item) => DropdownMenuItem(
                                  value: item.id,
                                  child: Text(item.displayName),
                                ),
                              )
                              .toList(),
                          onChanged: _controller.isBusy
                              ? null
                              : (value) {
                                  final next = value ?? '';
                                  if (next == _characterId) return;
                                  _controller.selectCharacter(next);
                                  setState(() => _characterId = next);
                                },
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            const Text('安全播放增益'),
                            Expanded(
                              child: Slider(
                                value: _gain,
                                min: 0.05,
                                max: 0.25,
                                divisions: 20,
                                label: _gain.toStringAsFixed(2),
                                onChanged: _controller.isBusy
                                    ? null
                                    : (value) => setState(() => _gain = value),
                              ),
                            ),
                            Text(_gain.toStringAsFixed(2)),
                          ],
                        ),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _saving || _controller.isBusy
                                ? null
                                : _save,
                            icon: const Icon(Icons.lock_outline),
                            label: Text(_saving ? '保存中…' : '安全保存'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: PeiLinkSpacing.section),
                const PeiLinkSectionHeader(title: '实体对话'),
                PeiLinkSurface(
                  child: Padding(
                    padding: const EdgeInsets.all(PeiLinkSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PhysicalSessionSummary(
                          turnCount: _controller.turnCount,
                          isBusy: _controller.isBusy,
                          onClear: _controller.clearSession,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _controller.message,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (_controller.transcript.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text('识别文本：${_controller.transcript}'),
                        ],
                        if (_controller.spokenReply.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text('实际朗读：${_controller.spokenReply}'),
                        ],
                        if (_controller.ttsReview case final review?) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Stage E：24 kHz PCM16 mono ${review.originalBytes} bytes'
                            ' → 16 kHz PCM16 mono ${review.pcm.length} bytes\n'
                            'peak=${review.stats.peak}  '
                            'RMS=${review.stats.rms.toStringAsFixed(1)}  '
                            'clipping=${review.stats.clipped}  '
                            'CRC32=${review.crc32.toRadixString(16).padLeft(8, '0').toUpperCase()}',
                          ),
                        ],
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _controller.isBusy
                              ? null
                              : () => _controller.check(_settings),
                          icon: const Icon(Icons.wifi_find),
                          label: const Text('检查 Phase 9 设备'),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: _controller.canRecord
                              ? () => _controller.record(_settings)
                              : null,
                          icon: const Icon(Icons.mic_none),
                          label: const Text('开始 8 秒录音'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _controller.canRecognizeOnly
                              ? () => _controller.recognizeOnly(_settings)
                              : null,
                          icon: const Icon(Icons.text_fields_rounded),
                          label: const Text('仅识别语音（Stage C）'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _controller.canSynthesizeOnly
                              ? () => _controller.synthesizeOnly(
                                  _settings,
                                  text: _stageEText,
                                )
                              : null,
                          icon: const Icon(Icons.graphic_eq_rounded),
                          label: const Text('仅生成 TTS 数据（Stage E）'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _controller.canPlayReviewedOnly
                              ? () => _controller.playReviewedOnly(_settings)
                              : null,
                          icon: const Icon(Icons.speaker_rounded),
                          label: const Text('仅播放已验收音频（Stage F）'),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: _controller.canContinue
                              ? () =>
                                    _controller.continueConversation(_settings)
                              : null,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('继续 AI 回复（将调用在线服务）'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: PeiLinkSpacing.lg),
                const Text(
                  '本页面不会自动录音、自动重试或写入正式聊天历史。Windows Host 不参与运行。',
                  style: PeiLinkTypography.secondary,
                ),
              ],
            ),
    );
  }
}

class PhysicalSessionSummary extends StatelessWidget {
  const PhysicalSessionSummary({
    required this.turnCount,
    required this.isBusy,
    required this.onClear,
    super.key,
  });

  final int turnCount;
  final bool isBusy;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          '本次实体会话：$turnCount 轮',
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
      TextButton.icon(
        onPressed: isBusy ? null : onClear,
        icon: const Icon(Icons.delete_sweep_outlined),
        label: const Text('清空实体会话'),
      ),
    ],
  );
}
