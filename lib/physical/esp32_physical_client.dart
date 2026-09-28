import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'pcm_audio_codec.dart';

class Esp32PhysicalClient {
  Esp32PhysicalClient({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  Uri _uri(String host, String path) {
    final input = host.trim();
    final parsed = Uri.tryParse(
      input.contains('://') ? input : 'http://$input',
    );
    if (parsed == null ||
        parsed.scheme != 'http' ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        !_isPrivateIpv4(parsed.host)) {
      throw const FormatException('ESP32 地址必须是私有局域网 IPv4 地址');
    }
    return Uri(scheme: 'http', host: parsed.host, port: 8080, path: path);
  }

  bool _isPrivateIpv4(String host) {
    final parts = host.split('.').map(int.tryParse).toList();
    if (parts.length != 4 ||
        parts.any((item) => item == null || item < 0 || item > 255)) {
      return false;
    }
    final a = parts[0]!;
    final b = parts[1]!;
    return a == 10 ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168);
  }

  Map<String, String> _headers(String key) => {
    'X-PeiLink-Key': key,
    'Connection': 'close',
  };

  Future<Esp32Status> status({
    required String host,
    required String key,
  }) async {
    final response = await _send(
      method: 'GET',
      uri: _uri(host, '/status'),
      headers: _headers(key),
      timeout: const Duration(seconds: 5),
    );
    final payload = _json(response, '设备状态');
    final result = Esp32Status.fromJson(payload);
    if (response.statusCode != 200 ||
        !result.ok ||
        (result.phase != 9 && result.phase != 11) ||
        (result.phase == 11 &&
            (result.captureMode != 'vad' || !result.fixedFallback)) ||
        result.state != 'idle' ||
        result.sampleRate != PcmAudioCodec.sampleRate ||
        result.bits != PcmAudioCodec.bits ||
        result.channels != PcmAudioCodec.channels ||
        result.recordSeconds != PcmAudioCodec.recordSeconds ||
        result.maxPlaybackBytes != PcmAudioCodec.maxPlaybackBytes ||
        result.rxErrors != 0 ||
        result.txErrors != 0) {
      throw const PhysicalProtocolException('ESP32 状态或音频参数不符合 Phase 9');
    }
    return result;
  }

  Future<PhysicalCapture> record({
    required String host,
    required String key,
  }) async {
    final response = await _send(
      method: 'POST',
      uri: _uri(host, '/record'),
      headers: _headers(key),
      timeout: const Duration(seconds: 60),
    );
    final captureMode = response.headers['x-capture-mode'];
    final vadState = response.headers['x-vad-state'];
    if (response.statusCode == 204 &&
        captureMode == 'vad' &&
        vadState == 'no_speech') {
      throw const PhysicalNoSpeechException('未检测到可识别语音');
    }
    if (response.statusCode != 200 ||
        response.headers['content-type']?.split(';').first !=
            'application/octet-stream') {
      throw PhysicalProtocolException(
        'ESP32 录音失败（HTTP ${response.statusCode}）',
      );
    }
    final pcm = response.bodyBytes;
    int header(String name, {int radix = 10}) {
      final raw = response.headers[name];
      final value = raw == null ? null : int.tryParse(raw, radix: radix);
      if (value == null) throw PhysicalProtocolException('录音响应缺少 $name');
      return value;
    }

    final expectedCrc = header('x-audio-crc32', radix: 16);
    final actualCrc = PcmAudioCodec.crc32(pcm);
    final isLegacyFixed = captureMode == null && vadState == null;
    final isVadCapture =
        captureMode == 'vad' &&
        (vadState == 'complete' || vadState == 'max_duration');
    final isFixedFallback =
        captureMode == 'fixed_fallback' && vadState == 'error';
    // Two distinct length contracts:
    //   * Phase 9 legacy fixed capture / Phase 11 `fixed_fallback`: exactly the
    //     8 s fixed recording (recordBytes).
    //   * Phase 11 dynamic VAD (`complete` / `max_duration`): any even length
    //     up to the firmware's derived dynamic capture maximum, which is
    //     longer than 8 s (history + speaking window).
    final lengthValid = isVadCapture
        ? pcm.isNotEmpty &&
              pcm.length.isEven &&
              pcm.length <= PcmAudioCodec.phase11MaxCaptureBytes
        : (isLegacyFixed || isFixedFallback) &&
              pcm.length == PcmAudioCodec.recordBytes;
    if (header('content-length') != pcm.length ||
        !lengthValid ||
        expectedCrc != actualCrc ||
        header('x-audio-sample-rate') != PcmAudioCodec.sampleRate ||
        header('x-audio-bits') != PcmAudioCodec.bits ||
        header('x-audio-channels') != PcmAudioCodec.channels) {
      throw const PhysicalInvalidRecordingException('录音长度、CRC 或格式校验失败');
    }
    final stats = PcmAudioCodec.stats(pcm);
    if (stats.peak != header('x-audio-peak') ||
        stats.isEffectivelySilent ||
        stats.hasExcessiveClipping) {
      throw const PhysicalInvalidRecordingException('录音音量质量检查失败');
    }
    return PhysicalCapture(
      pcm: pcm,
      stats: stats,
      crc32: actualCrc,
      captureMode: captureMode ?? 'fixed',
      vadState: vadState,
      recordingId: int.tryParse(response.headers['x-audio-recording-id'] ?? ''),
    );
  }

  Future<void> play({
    required String host,
    required String key,
    required Uint8List pcm,
    required double gain,
  }) async {
    if (gain <= 0 || gain > 0.25) {
      throw const PhysicalProtocolException('播放增益超出安全上限');
    }
    PcmAudioCodec.validatePcm(pcm);
    final headers = {
      ..._headers(key),
      'Content-Type': 'application/octet-stream',
      'X-Audio-CRC32': PcmAudioCodec.crc32(
        pcm,
      ).toRadixString(16).padLeft(8, '0').toUpperCase(),
      'X-Audio-Sample-Rate': '${PcmAudioCodec.sampleRate}',
      'X-Audio-Bits': '${PcmAudioCodec.bits}',
      'X-Audio-Channels': '${PcmAudioCodec.channels}',
      'X-Audio-Gain-Q15': '${(gain * 32768).round()}',
    };
    final duration = pcm.length / (PcmAudioCodec.sampleRate * 2);
    final response = await _send(
      method: 'POST',
      uri: _uri(host, '/audio'),
      headers: headers,
      body: pcm,
      timeout: Duration(seconds: duration.ceil() + 30),
    );
    final payload = _json(response, '播放结果');
    if (response.statusCode != 200 ||
        payload['ok'] != true ||
        payload['played'] != true ||
        payload['received_bytes'] != pcm.length ||
        payload['state'] != 'idle' ||
        payload['rx_errors'] != 0 ||
        payload['tx_errors'] != 0) {
      throw const PhysicalProtocolException('ESP32 未确认安全完整播放');
    }
  }

  Map<String, dynamic> _json(http.Response response, String operation) {
    try {
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (value is Map<String, dynamic>) return value;
    } catch (_) {}
    throw PhysicalProtocolException('$operation返回了无效数据');
  }

  Future<http.Response> _send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required Duration timeout,
    Uint8List? body,
  }) async {
    final request = http.Request(method, uri)
      ..followRedirects = false
      ..headers.addAll(headers);
    if (body != null) request.bodyBytes = body;
    final streamed = await _client.send(request).timeout(timeout);
    if (streamed.isRedirect ||
        (streamed.statusCode >= 300 && streamed.statusCode < 400)) {
      throw const PhysicalProtocolException('ESP32 响应包含不允许的重定向');
    }
    return http.Response.fromStream(streamed);
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}

class PhysicalCapture {
  const PhysicalCapture({
    required this.pcm,
    required this.stats,
    required this.crc32,
    this.captureMode = 'fixed',
    this.vadState,
    this.recordingId,
  });
  final Uint8List pcm;
  final PcmStats stats;
  final int crc32;
  final String captureMode;
  final String? vadState;
  final int? recordingId;
}

class Esp32Status {
  const Esp32Status({
    required this.ok,
    required this.phase,
    required this.state,
    required this.sampleRate,
    required this.bits,
    required this.channels,
    required this.recordSeconds,
    required this.maxPlaybackBytes,
    required this.rxErrors,
    required this.txErrors,
    this.captureMode = 'fixed',
    this.fixedFallback = false,
  });
  factory Esp32Status.fromJson(Map<String, dynamic> json) => Esp32Status(
    ok: json['ok'] == true,
    phase: json['phase'] as int? ?? 0,
    state: json['state']?.toString() ?? '',
    sampleRate: json['sample_rate'] as int? ?? 0,
    bits: json['bits'] as int? ?? 0,
    channels: json['channels'] as int? ?? 0,
    recordSeconds: json['record_seconds'] as int? ?? 0,
    maxPlaybackBytes: json['max_playback_bytes'] as int? ?? 0,
    rxErrors: json['rx_errors'] as int? ?? -1,
    txErrors: json['tx_errors'] as int? ?? -1,
    captureMode: json['capture_mode']?.toString() ?? 'fixed',
    fixedFallback: json['fixed_fallback'] == true,
  );
  final bool ok;
  final int phase,
      sampleRate,
      bits,
      channels,
      recordSeconds,
      maxPlaybackBytes,
      rxErrors,
      txErrors;
  final String state;
  final String captureMode;
  final bool fixedFallback;
}

class PhysicalProtocolException implements Exception {
  const PhysicalProtocolException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PhysicalInvalidRecordingException extends PhysicalProtocolException {
  const PhysicalInvalidRecordingException(super.message);
}

class PhysicalNoSpeechException extends PhysicalProtocolException {
  const PhysicalNoSpeechException(super.message);
}
