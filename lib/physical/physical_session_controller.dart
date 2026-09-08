import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';
import '../services/api_settings_storage_service.dart';
import '../services/core_bridge_service.dart';
import 'doubao_speech_clients.dart';
import 'esp32_physical_client.dart';
import 'pcm_audio_codec.dart';
import 'physical_host_settings.dart';
import 'physical_speech_contract.dart';
import 'physical_session_memory.dart';

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
  bool _fullTurnActive = false;
  bool _disposed = false;
  String _sessionCharacterId = '';

  PhysicalSessionStage stage = PhysicalSessionStage.idle;
  String message = '请先保存配置并检查设备';
  String transcript = '';
  String displayReply = '';
  String spokenReply = '';
  PhysicalTtsReview? ttsReview;
  PhysicalE2ETiming? lastEndToEndTiming;
  String lastSpeechFilterNote = '';
  PhysicalContractDiagnostics? speechContractDiagnostics;
  String? ttsInputExact;
  bool? get ttsInputMatchesSpoken =>
      ttsInputExact == null ? null : ttsInputExact == spokenReply;

  void _clearSpeechDiagnostics() {
    speechContractDiagnostics = null;
    ttsInputExact = null;
  }
  PhysicalCapture? _capture;
  AsrTranscribeStats? lastAsrStats;
  bool _deviceReady = false;
  bool get deviceReady => _deviceReady;
  bool get isBusy =>
      _fullTurnActive ||
      _operationActive ||
      const {
        PhysicalSessionStage.checking,
        PhysicalSessionStage.recording,
        PhysicalSessionStage.recognizing,
        PhysicalSessionStage.thinking,
        PhysicalSessionStage.synthesizing,
        PhysicalSessionStage.playing,
      }.contains(stage);
  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  void _throwIfDisposed() {
    if (_disposed) throw const _PhysicalDisposedException();
  }
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
    if (_disposed || isBusy) return;
    _clearSpeechDiagnostics();
    _sessionMemory.clear();
    notifyListeners();
  }

  void selectCharacter(String characterId) {
    if (_disposed || isBusy) return;
    final normalized = characterId.trim();
    if (_sessionCharacterId == normalized) return;
    _clearSpeechDiagnostics();
    _sessionCharacterId = normalized;
    _sessionMemory.clear();
    notifyListeners();
  }

  Future<void> check(PhysicalHostSettings settings) async {
    if (_disposed || isBusy) return;
    if (!settings.isDeviceConfigured) return _fail('请先填写 ESP32 地址和请求密钥');
    _deviceReady = false;
    await _run(PhysicalSessionStage.checking, '正在检查 Phase 9 设备…', () async {
      await _device.status(host: settings.esp32Host, key: settings.requestKey);
      _throwIfDisposed();
      _deviceReady = true;
      stage = PhysicalSessionStage.ready;
      message = '设备就绪，可以开始 8 秒录音';
    });
  }

  Future<void> record(PhysicalHostSettings settings) async {
    if (_disposed || !canRecord || isBusy) return;
    _clearSpeechDiagnostics();
    selectCharacter(settings.characterId);
    transcript = '';
    displayReply = '';
    spokenReply = '';
    ttsReview = null;
    lastEndToEndTiming = null;
    lastSpeechFilterNote = '';
    lastAsrStats = null;
    _capture = null;
    await _run(PhysicalSessionStage.recording, '正在录音，请现在说话（固定 8 秒）…', () async {
      final capture = await _device.record(
        host: settings.esp32Host,
        key: settings.requestKey,
      );
      _throwIfDisposed();
      _capture = capture;
      stage = PhysicalSessionStage.review;
      message = '录音有效。点击“继续 AI 回复”后才会调用在线服务';
    });
  }

  Future<void> recognizeOnly(PhysicalHostSettings settings) async {
    if (_disposed || !canRecognizeOnly || isBusy) return;
    if (!settings.isCloudConfigured) return _fail('请填写豆包语音 API Key');
    final pcm = _capture!.pcm;
    await _run(PhysicalSessionStage.recognizing, '正在识别语音…', () async {
      final recognized = await _asr.transcribe(
        pcm: pcm,
        apiKey: settings.volcengineApiKey,
        boostingTableId: settings.boostingTableId,
        onStats: (stats) => lastAsrStats = stats,
      );
      _throwIfDisposed();
      transcript = recognized;
      stage = PhysicalSessionStage.review;
      message = 'ASR 识别完成，已停止在 Stage C';
    });
  }

  Future<void> replyOnly(PhysicalHostSettings settings) async {
    if (_disposed || !canReplyOnly || isBusy) return;
    _clearSpeechDiagnostics();
    if (settings.characterId.trim().isEmpty) return _fail('请选择 Physical 角色');
    await _run(PhysicalSessionStage.thinking, '裴简澈正在思考…', () async {
      if (!await _modelConfigured()) {
        _fail('请先配置正式聊天模型');
        return;
      }
      _throwIfDisposed();
      final physical = await _requestPhysicalReply(settings);
      _throwIfDisposed();
      displayReply = physical.displayReply;
      spokenReply = physical.spokenReply;
      lastSpeechFilterNote = physical.fallbackReason;
      stage = PhysicalSessionStage.review;
      message = 'Core 回复完成，已停止在 Stage D';
    });
  }

  Future<void> synthesizeOnly(
    PhysicalHostSettings settings, {
    required String text,
  }) async {
    if (_disposed || !canSynthesizeOnly) return;
    _clearSpeechDiagnostics();
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
        _throwIfDisposed();
        final pcm16 = await compute(PcmAudioCodec.resample24kTo16k, pcm24);
        _throwIfDisposed();
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
    if (_disposed || !canPlayReviewedOnly) return;
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
      _throwIfDisposed();
      stage = PhysicalSessionStage.completed;
      _deviceReady = true;
      message = 'Stage F 单次播放完成';
    });
  }

  Future<void> continueConversation(PhysicalHostSettings settings) async {
    if (_disposed || !canContinue || isBusy) return;
    if (!settings.isConfigured) return _fail('请补全豆包 API Key 和 Physical 角色');
    final capture = _capture!;
    await _run(
      PhysicalSessionStage.recognizing,
      '正在识别语音…',
      () => _runTurnFromCapture(settings, capture),
    );
  }

  /// Runs one complete Physical turn from the device-ready state:
  /// status check -> 8s record -> ASR -> formal Core reply -> TTS ->
  /// 24k-to-16k conversion -> /audio playback -> session append.
  ///
  /// Unlike the staged debug methods, this entry always synthesizes the text
  /// returned by the current formal LLM turn (`spokenReply`) and never uses
  /// the fixed Stage E debug sentence.
  Future<void> startEndToEndTurn(PhysicalHostSettings settings) async {
    if (_disposed || isBusy) return;
    _clearSpeechDiagnostics();
    if (!settings.isConfigured) {
      return _fail('请补全豆包 API Key 和 Physical 角色');
    }
    if (settings.characterId.trim().isEmpty) {
      return _fail('请选择 Physical 角色');
    }

    _fullTurnActive = true;
    notifyListeners();
    final meter = _E2EMeter();
    lastEndToEndTiming = null;
    notifyListeners();
    try {
      bool configured;
      try {
        configured = await _measureTurnPhase(
          meter,
          PhysicalE2EFailureStage.model,
          _modelConfigured,
        );
        if (_disposed) return;
      } catch (_) {
        if (_disposed) return;
        meter.failedStage = PhysicalE2EFailureStage.model;
        _fail('无法检查正式聊天模型配置');
        lastEndToEndTiming = meter.build();
        notifyListeners();
        return;
      }
      if (!configured) {
        if (_disposed) return;
        meter.failedStage = PhysicalE2EFailureStage.model;
        _fail('请先配置正式聊天模型');
        lastEndToEndTiming = meter.build();
        notifyListeners();
        return;
      }

      final normalized = settings.characterId.trim();
      if (_sessionCharacterId != normalized) {
        _sessionCharacterId = normalized;
        _sessionMemory.clear();
      }
      transcript = '';
      displayReply = '';
      spokenReply = '';
      ttsReview = null;
      lastSpeechFilterNote = '';
      lastAsrStats = null;
      _capture = null;
      if (_disposed) return;

      await _run(
        PhysicalSessionStage.checking,
        '正在准备实体对话…',
        () async {
          await _measureTurnPhase(
            meter,
            PhysicalE2EFailureStage.status,
            () => _device.status(
              host: settings.esp32Host,
              key: settings.requestKey,
            ),
          );
          _throwIfDisposed();
          _deviceReady = true;
          stage = PhysicalSessionStage.recording;
          message = '正在录音，请现在说话（固定 8 秒）…';
          notifyListeners();

          final capture = await _measureTurnPhase(
            meter,
            PhysicalE2EFailureStage.record,
            () => _device.record(
              host: settings.esp32Host,
              key: settings.requestKey,
            ),
          );
          _throwIfDisposed();
          _capture = capture;
          stage = PhysicalSessionStage.review;
          message = '录音有效，正在继续 AI 对话…';
          notifyListeners();

          await _runTurnFromCapture(settings, capture, meter: meter);
        },
      );
      if (!_disposed) {
        lastEndToEndTiming = meter.build();
        notifyListeners();
      }
    } finally {
      _fullTurnActive = false;
      notifyListeners();
    }
  }

  Future<void> _runTurnFromCapture(
    PhysicalHostSettings settings,
    PhysicalCapture capture, {
    _E2EMeter? meter,
  }) async {
    final pcm = capture.pcm;
    _clearSpeechDiagnostics();
    _throwIfDisposed();
    stage = PhysicalSessionStage.recognizing;
    message = '正在识别语音…';
    notifyListeners();
    final recognized = await _measureTurnPhase(
      meter,
      PhysicalE2EFailureStage.asr,
      () async {
        final text = await _asr.transcribe(
          pcm: pcm,
          apiKey: settings.volcengineApiKey,
          boostingTableId: settings.boostingTableId,
          onStats: (stats) => lastAsrStats = stats,
        );
        if (text.trim().isEmpty) {
          throw const SpeechCloudException('ASR 返回空文本');
        }
        return text;
      },
    );
    _throwIfDisposed();
    transcript = recognized;

    stage = PhysicalSessionStage.thinking;
    message = '裴简澈正在思考…';
    notifyListeners();
    final spoken = await _measureTurnPhase(
      meter,
      PhysicalE2EFailureStage.llm,
      () async {
        final physical = await _requestPhysicalReply(settings);
        displayReply = physical.displayReply;
        lastSpeechFilterNote = physical.fallbackReason;
        if (physical.spokenReply.trim().isEmpty) {
          throw const FormatException('AI 回复没有可朗读内容');
        }
        return physical.spokenReply;
      },
    );
    _throwIfDisposed();
    spokenReply = spoken;

    stage = PhysicalSessionStage.synthesizing;
    message = '正在生成实体语音…';
    notifyListeners();
    final pcm24 = await _measureTurnPhase(
      meter,
      PhysicalE2EFailureStage.tts,
      () {
        final text = spokenReply;
        ttsInputExact = text;
        return _tts.synthesize(
          text: text,
          apiKey: settings.volcengineApiKey,
        );
      },
    );
    _throwIfDisposed();
    final pcm16 = await _measureTurnPhase(
      meter,
      PhysicalE2EFailureStage.resample,
      () async {
        final converted = await compute(PcmAudioCodec.resample24kTo16k, pcm24);
        final stats = PcmAudioCodec.stats(converted);
        if (stats.isEffectivelySilent || stats.hasExcessiveClipping) {
          throw const FormatException('转换后的 TTS 音频质量检查失败');
        }
        return converted;
      },
    );
    _throwIfDisposed();

    stage = PhysicalSessionStage.playing;
    message = '正在发送并等待实体喇叭播放完成…';
    notifyListeners();
    await _measureTurnPhase(
      meter,
      PhysicalE2EFailureStage.audio,
      () => _device.play(
        host: settings.esp32Host,
        key: settings.requestKey,
        pcm: pcm16,
        gain: settings.playbackGain,
      ),
    );
    _throwIfDisposed();
    _sessionMemory.add(
      PhysicalSessionTurn(
        userTranscript: transcript,
        assistantSpokenText: spokenReply,
        displayText: displayReply.isEmpty ? spokenReply : displayReply,
        completedAt: DateTime.now(),
      ),
    );
    _deviceReady = true;
    stage = PhysicalSessionStage.ready;
    message = '本轮 Physical 对话完成';
    _capture = null;
  }

  Future<PhysicalSpeechReply> _requestPhysicalReply(
    PhysicalHostSettings settings,
  ) async {
    final raw =
        await (_coreReply?.call(
              settings.characterId,
              transcript,
              _sessionMemory.toChatMessages(),
            ) ??
            _coreService!.reply(
              characterId: settings.characterId,
              userText: transcript,
              transientContext: _sessionMemory.toChatMessages(),
              physicalSpeechContract: PhysicalSpeechContract.instruction,
            ));
    _throwIfDisposed();
    final physical = PhysicalSpeechContractParser.resolve(raw);
    speechContractDiagnostics = physical.diagnostics;
    return physical;
  }

  Future<T> _measureTurnPhase<T>(
    _E2EMeter? meter,
    PhysicalE2EFailureStage stage,
    Future<T> Function() action,
  ) async {
    if (meter == null) return action();
    final watch = Stopwatch()..start();
    try {
      final result = await action();
      watch.stop();
      meter.record(stage, watch.elapsedMilliseconds);
      return result;
    } catch (_) {
      meter.failedStage = stage;
      rethrow;
    }
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
      if (_disposed || error is _PhysicalDisposedException) return;
      _recoverFromFailure(stage, error);
    } finally {
      _operationActive = false;
      if (!_disposed) notifyListeners();
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
    if (failedStage == PhysicalSessionStage.recognizing) {
      // ASR did not produce a usable current transcript. Never show text from
      // the previous turn or partial diagnostics as if it belonged to this one.
      transcript = '';
      displayReply = '';
      spokenReply = '';
      lastSpeechFilterNote = '';
      _clearSpeechDiagnostics();
    }
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
    _disposed = true;
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

enum PhysicalE2EFailureStage {
  model,
  status,
  record,
  asr,
  llm,
  tts,
  resample,
  audio,
}

class _PhysicalDisposedException implements Exception {
  const _PhysicalDisposedException();
}

class PhysicalE2ETiming {
  const PhysicalE2ETiming({
    this.statusMs,
    this.recordMs,
    this.asrMs,
    this.llmMs,
    this.ttsMs,
    this.resampleMs,
    this.audioMs,
    this.totalMs,
    this.failedStage,
  });

  final int? statusMs;
  final int? recordMs;
  final int? asrMs;
  final int? llmMs;
  final int? ttsMs;
  final int? resampleMs;
  final int? audioMs;
  final int? totalMs;
  final PhysicalE2EFailureStage? failedStage;
}

class _E2EMeter {
  final Stopwatch total = Stopwatch()..start();
  int? statusMs;
  int? recordMs;
  int? asrMs;
  int? llmMs;
  int? ttsMs;
  int? resampleMs;
  int? audioMs;
  PhysicalE2EFailureStage? failedStage;

  void record(PhysicalE2EFailureStage stage, int milliseconds) {
    switch (stage) {
      case PhysicalE2EFailureStage.model:
        break;
      case PhysicalE2EFailureStage.status:
        statusMs = milliseconds;
        break;
      case PhysicalE2EFailureStage.record:
        recordMs = milliseconds;
        break;
      case PhysicalE2EFailureStage.asr:
        asrMs = milliseconds;
        break;
      case PhysicalE2EFailureStage.llm:
        llmMs = milliseconds;
        break;
      case PhysicalE2EFailureStage.tts:
        ttsMs = milliseconds;
        break;
      case PhysicalE2EFailureStage.resample:
        resampleMs = milliseconds;
        break;
      case PhysicalE2EFailureStage.audio:
        audioMs = milliseconds;
        break;
    }
  }

  PhysicalE2ETiming build() {
    total.stop();
    return PhysicalE2ETiming(
      statusMs: statusMs,
      recordMs: recordMs,
      asrMs: asrMs,
      llmMs: llmMs,
      ttsMs: ttsMs,
      resampleMs: resampleMs,
      audioMs: audioMs,
      totalMs: total.elapsedMilliseconds,
      failedStage: failedStage,
    );
  }
}
