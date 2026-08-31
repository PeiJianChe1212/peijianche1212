import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';
import '../services/api_settings_storage_service.dart';
import '../services/core_bridge_service.dart';
import 'doubao_speech_clients.dart';
import 'esp32_physical_client.dart';
import 'pcm_audio_codec.dart';
import 'physical_host_settings.dart';
import 'physical_session_memory.dart';
import 'physical_speech_text_adapter.dart';

enum PhysicalSessionStage {
  idle,
  checking,
  ready,
  recording,
  review,
  recognizing,
  thinking,
  synthesizing,
  playing,
  completed,
  error,
}

typedef PhysicalCoreReply =
    Future<String> Function(
      String characterId,
      String userText,
      List<ChatMessage> transientContext,
    );
typedef PhysicalModelConfigured = Future<bool> Function();

class PhysicalSessionController extends ChangeNotifier {
  PhysicalSessionController({
    Esp32PhysicalClient? device,
    DoubaoAsrClient? asr,
    DoubaoTtsClient? tts,
    PhysicalCoreReply? coreReply,
    PhysicalModelConfigured? modelConfigured,
  }) : _device = device ?? Esp32PhysicalClient(),
       _asr = asr ?? DoubaoAsrClient(),
       _tts = tts ?? DoubaoTtsClient(),
       _coreService = coreReply == null ? CoreBridgeService() : null,
       _coreReply = coreReply,
       _modelConfigured =
           modelConfigured ??
           (() async =>
               (await ApiSettingsStorageService().loadSettings()).isConfigured);

  final Esp32PhysicalClient _device;
  final DoubaoAsrClient _asr;
  final DoubaoTtsClient _tts;
  final CoreBridgeService? _coreService;
  final PhysicalCoreReply? _coreReply;
  final PhysicalModelConfigured _modelConfigured;
  final PhysicalSessionMemory _sessionMemory = PhysicalSessionMemory();
  bool _operationActive = false;
  String _sessionCharacterId = '';

  PhysicalSessionStage stage = PhysicalSessionStage.idle;
  String message = '请先保存配置并检查设备';
  String transcript = '';
  String spokenReply = '';
  PhysicalTtsReview? ttsReview;
  PhysicalCapture? _capture;
  bool _deviceReady = false;
  bool get deviceReady => _deviceReady;
  bool get isBusy =>
      _operationActive ||
      const {
        PhysicalSessionStage.checking,
        PhysicalSessionStage.recording,
        PhysicalSessionStage.recognizing,
        PhysicalSessionStage.thinking,
        PhysicalSessionStage.synthesizing,
        PhysicalSessionStage.playing,
      }.contains(stage);
  bool get canRecord =>
      _deviceReady &&
      (stage == PhysicalSessionStage.ready ||
          stage == PhysicalSessionStage.completed);
  bool get canContinue =>
      stage == PhysicalSessionStage.review && _capture != null;
  bool get canRecognizeOnly => canContinue && transcript.isEmpty;
  bool get canReplyOnly =>
      canContinue && transcript.isNotEmpty && spokenReply.isEmpty;
  bool get canSynthesizeOnly => !isBusy && ttsReview == null;
  bool get canPlayReviewedOnly => !isBusy && ttsReview != null;
  List<PhysicalSessionTurn> get turns => _sessionMemory.turns;
  int get turnCount => _sessionMemory.turnCount;

  void clearSession() {
    if (isBusy) return;
    _sessionMemory.clear();
    notifyListeners();
  }

  void selectCharacter(String characterId) {
    if (isBusy) return;
    final normalized = characterId.trim();
    if (_sessionCharacterId == normalized) return;
    _sessionCharacterId = normalized;
    _sessionMemory.clear();
    notifyListeners();
  }

  Future<void> check(PhysicalHostSettings settings) async {
    if (isBusy) return;
    if (!settings.isDeviceConfigured) return _fail('请先填写 ESP32 地址和请求密钥');
    _deviceReady = false;
    await _run(PhysicalSessionStage.checking, '正在检查 Phase 9 设备…', () async {
      await _device.status(host: settings.esp32Host, key: settings.requestKey);
      _deviceReady = true;
      stage = PhysicalSessionStage.ready;
      message = '设备就绪，可以开始 8 秒录音';
    });
  }

  Future<void> record(PhysicalHostSettings settings) async {
    if (!canRecord || isBusy) return;
    selectCharacter(settings.characterId);
    transcript = '';
    spokenReply = '';
    ttsReview = null;
    _capture = null;
    await _run(PhysicalSessionStage.recording, '正在录音，请现在说话（固定 8 秒）…', () async {
      final capture = await _device.record(
        host: settings.esp32Host,
        key: settings.requestKey,
      );
      _capture = capture;
      stage = PhysicalSessionStage.review;
      message = '录音有效。点击“继续 AI 回复”后才会调用在线服务';
    });
  }

  Future<void> recognizeOnly(PhysicalHostSettings settings) async {
    if (!canRecognizeOnly || isBusy) return;
    if (!settings.isCloudConfigured) return _fail('请填写豆包语音 API Key');
    final pcm = _capture!.pcm;
    await _run(PhysicalSessionStage.recognizing, '正在识别语音…', () async {
      transcript = await _asr.transcribe(
        pcm: pcm,
        apiKey: settings.volcengineApiKey,
        boostingTableId: settings.boostingTableId,
      );
      stage = PhysicalSessionStage.review;
      message = 'ASR 识别完成，已停止在 Stage C';
    });
  }

  Future<void> replyOnly(PhysicalHostSettings settings) async {
    if (!canReplyOnly || isBusy) return;
    if (settings.characterId.trim().isEmpty) return _fail('请选择 Physical 角色');
    await _run(PhysicalSessionStage.thinking, '裴简澈正在思考…', () async {
      if (!await _modelConfigured()) {
        _fail('请先配置正式聊天模型');
        return;
      }
      final reply =
          await (_coreReply?.call(
                settings.characterId,
                transcript,
                _sessionMemory.toChatMessages(),
              ) ??
              _coreService!.reply(
                characterId: settings.characterId,
                userText: transcript,
                transientContext: _sessionMemory.toChatMessages(),
              ));
      spokenReply = PhysicalSpeechTextAdapter.fromCoreReply(reply);
      stage = PhysicalSessionStage.review;
      message = 'Core 回复完成，已停止在 Stage D';
    });
  }

  Future<void> synthesizeOnly(
    PhysicalHostSettings settings, {
    required String text,
  }) async {
    if (!canSynthesizeOnly) return;
    if (!settings.isCloudConfigured) return _fail('请填写豆包语音 API Key');
    final speechText = text.trim();
    if (speechText.isEmpty) return _fail('待合成文本为空');
    await _run(
      PhysicalSessionStage.synthesizing,
      '正在生成 Stage E 实体语音…',
      () async {
        final pcm24 = await _tts.synthesize(
          text: speechText,
          apiKey: settings.volcengineApiKey,
        );
        final pcm16 = await compute(PcmAudioCodec.resample24kTo16k, pcm24);
        final stats = PcmAudioCodec.stats(pcm16);
        if (stats.isEffectivelySilent || stats.hasExcessiveClipping) {
          throw const FormatException('转换后的 TTS 音频质量检查失败');
        }
        ttsReview = PhysicalTtsReview(
          originalBytes: pcm24.length,
          pcm: pcm16,
          stats: stats,
          crc32: PcmAudioCodec.crc32(pcm16),
        );
        spokenReply = speechText;
        stage = PhysicalSessionStage.review;
        message = 'TTS 数据验收完成，已停止在 Stage E';
      },
    );
  }

  Future<void> playReviewedOnly(PhysicalHostSettings settings) async {
    if (!canPlayReviewedOnly) return;
    if (!settings.isDeviceConfigured) {
      return _fail('请先填写 ESP32 地址和请求密钥');
    }
    final pcm = ttsReview!.pcm;
    await _run(PhysicalSessionStage.playing, '正在执行 Stage F 单次播放…', () async {
      await _device.play(
        host: settings.esp32Host,
        key: settings.requestKey,
        pcm: pcm,
        gain: settings.playbackGain,
      );
      stage = PhysicalSessionStage.completed;
      _deviceReady = true;
      message = 'Stage F 单次播放完成';
    });
  }

  Future<void> continueConversation(PhysicalHostSettings settings) async {
    if (!canContinue || isBusy) return;
    if (!settings.isConfigured) return _fail('请补全豆包 API Key 和 Physical 角色');
    final pcm = _capture!.pcm;
    await _run(PhysicalSessionStage.recognizing, '正在识别语音…', () async {
      transcript = await _asr.transcribe(
        pcm: pcm,
        apiKey: settings.volcengineApiKey,
        boostingTableId: settings.boostingTableId,
      );
      stage = PhysicalSessionStage.thinking;
      message = '裴简澈正在思考…';
      notifyListeners();
      final reply =
          await (_coreReply?.call(
                settings.characterId,
                transcript,
                _sessionMemory.toChatMessages(),
              ) ??
              _coreService!.reply(
                characterId: settings.characterId,
                userText: transcript,
                transientContext: _sessionMemory.toChatMessages(),
              ));
      spokenReply = PhysicalSpeechTextAdapter.fromCoreReply(reply);
      stage = PhysicalSessionStage.synthesizing;
      message = '正在生成实体语音…';
      notifyListeners();
      final pcm24 = await _tts.synthesize(
        text: spokenReply,
        apiKey: settings.volcengineApiKey,
      );
      final pcm16 = await compute(PcmAudioCodec.resample24kTo16k, pcm24);
      final stats = PcmAudioCodec.stats(pcm16);
      if (stats.isEffectivelySilent || stats.hasExcessiveClipping) {
        throw const FormatException('转换后的 TTS 音频质量检查失败');
      }
      stage = PhysicalSessionStage.playing;
      message = '正在发送并等待实体喇叭播放完成…';
      notifyListeners();
      await _device.play(
        host: settings.esp32Host,
        key: settings.requestKey,
        pcm: pcm16,
        gain: settings.playbackGain,
      );
      _sessionMemory.add(
        PhysicalSessionTurn(
          userTranscript: transcript,
          assistantSpokenText: spokenReply,
          completedAt: DateTime.now(),
        ),
      );
      _deviceReady = true;
      stage = PhysicalSessionStage.ready;
      message = '本轮 Physical 对话完成';
      _capture = null;
    });
  }

  Future<void> _run(
    PhysicalSessionStage next,
    String label,
    Future<void> Function() action,
  ) async {
    if (_operationActive) return;
    _operationActive = true;
    stage = next;
    message = label;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      _recoverFromFailure(stage, error);
    } finally {
      _operationActive = false;
      notifyListeners();
    }
  }

  void _fail(String value) {
    stage = _deviceReady
        ? PhysicalSessionStage.ready
        : PhysicalSessionStage.error;
    message = value;
    notifyListeners();
  }

  void _recoverFromFailure(PhysicalSessionStage failedStage, Object error) {
    _capture = null;
    ttsReview = null;
    if (error is PhysicalInvalidRecordingException && _deviceReady) {
      stage = PhysicalSessionStage.ready;
    } else if (failedStage == PhysicalSessionStage.recording ||
        failedStage == PhysicalSessionStage.playing ||
        failedStage == PhysicalSessionStage.checking) {
      _deviceReady = false;
      stage = PhysicalSessionStage.error;
    } else {
      stage = _deviceReady
          ? PhysicalSessionStage.ready
          : PhysicalSessionStage.error;
    }
    message = _friendlyError(error);
    notifyListeners();
  }

  String _friendlyError(Object error) {
    if (error is PhysicalProtocolException) return error.message;
    if (error is SpeechCloudException) return error.message;
    if (error is FormatException) return error.message;
    return '本轮已安全停止：${error.runtimeType}';
  }

  @override
  void dispose() {
    _device.dispose();
    _asr.dispose();
    _tts.dispose();
    _coreService?.dispose();
    super.dispose();
  }
}

class PhysicalTtsReview {
  const PhysicalTtsReview({
    required this.originalBytes,
    required this.pcm,
    required this.stats,
    required this.crc32,
  });

  final int originalBytes;
  final Uint8List pcm;
  final PcmStats stats;
  final int crc32;
}
