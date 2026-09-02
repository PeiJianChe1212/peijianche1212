import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'pcm_audio_codec.dart';
import 'pcm_audio_gain.dart';

/// ASR 转录的脱敏统计信息。
///
/// 仅记录数值统计和状态码，不包含 API Key、音频内容或 base64 数据。
/// 输入统计来自原始 PCM，输出统计来自实际提交 ASR 的同一个 asrPcm。
class AsrTranscribeStats {
  const AsrTranscribeStats({
    required this.inputBytes,
    required this.inputPeak,
    required this.inputRms,
    required this.selectedGain,
    required this.gainReason,
    required this.outputPeak,
    required this.outputRms,
    required this.outputClippingRatio,
    this.asrStatusCode,
    this.asrMessage,
    this.asrLogId,
    this.segments = const [],
    this.resultStructure,
    required this.success,
  });

  /// 输入 PCM 字节数。
  final int inputBytes;

  /// 输入 PCM 峰值。
  final int inputPeak;

  /// 输入 PCM RMS。
  final double inputRms;

  /// 实际选择的增益倍数。
  final double selectedGain;

  /// 增益原因。
  final GainReason gainReason;

  /// 增益后输出 PCM 峰值。
  final int outputPeak;

  /// 增益后输出 PCM RMS。
  final double outputRms;

  /// 增益后输出削波比例。
  final double outputClippingRatio;

  /// ASR 最终状态码（成功或失败）。
  final String? asrStatusCode;

  /// ASR 状态消息（脱敏）。
  final String? asrMessage;

  /// ASR 请求 logid（如可获得）。
  final String? asrLogId;

  /// One-second statistics for the original input and uploaded PCM.
  /// The final segment may be shorter than one second for short recordings.
  final List<AsrTranscribeSegment> segments;

  /// Final successful query response structure without recognized text.
  final AsrResultStructure? resultStructure;

  /// ASR 是否成功。
  final bool success;

  @override
  String toString() =>
      'AsrTranscribeStats(input=${inputBytes}B peak=$inputPeak rms=${inputRms.toStringAsFixed(1)} '
      'gain=${selectedGain.toStringAsFixed(2)}($gainReason) '
      'outPeak=$outputPeak outRms=${outputRms.toStringAsFixed(1)} '
      'clip=${(outputClippingRatio * 100).toStringAsFixed(3)}% '
      'segments=${segments.length} resultStructure=$resultStructure '
      'status=$asrStatusCode success=$success)';
}

/// Desensitized shape of the final ASR result. No recognized text is retained.
class AsrResultStructure {
  const AsrResultStructure({
    required this.resultTextLength,
    required this.utterances,
  });

  final int resultTextLength;
  final List<AsrUtteranceStructure> utterances;

  int get utteranceCount => utterances.length;

  @override
  String toString() =>
      'AsrResultStructure(textLength=$resultTextLength utterances=$utterances)';
}

/// Desensitized shape of one final ASR utterance.
class AsrUtteranceStructure {
  const AsrUtteranceStructure({
    required this.textLength,
    this.startTime,
    this.endTime,
  });

  final int textLength;
  final num? startTime;
  final num? endTime;

  @override
  String toString() =>
      'AsrUtteranceStructure(textLength=$textLength start=$startTime end=$endTime)';
}

/// Per-second statistics for the exact PCM buffers used by an ASR request.
class AsrTranscribeSegment {
  const AsrTranscribeSegment({
    required this.startSecond,
    required this.endSecond,
    required this.inputPeak,
    required this.inputRms,
    required this.outputPeak,
    required this.outputRms,
  });

  final double startSecond;
  final double endSecond;
  final int inputPeak;
  final double inputRms;
  final int outputPeak;
  final double outputRms;
}

class DoubaoAsrClient {
  DoubaoAsrClient({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;
  final http.Client _client;
  final bool _ownsClient;
  static final _submit = Uri.parse(
    'https://openspeech.bytedance.com/api/v3/auc/bigmodel/submit',
  );
  static final _query = Uri.parse(
    'https://openspeech.bytedance.com/api/v3/auc/bigmodel/query',
  );
  static const _resource = 'volc.seedasr.auc';

  Future<String> transcribe({
    required Uint8List pcm,
    required String apiKey,
    String boostingTableId = '',
    void Function(AsrTranscribeStats stats)? onStats,
  }) async {
    final requestId = _uuid();
    // ASR 上传前应用自适应增益：仅生成处理副本，原始 PCM 不变
    final gainResult = PcmAudioGain.applyAdaptiveGain(pcm);
    final asrPcm = gainResult.output;

    // 构建脱敏统计基础信息（来自实际上传的同一个 asrPcm）
    AsrTranscribeStats buildStats({
      String? statusCode,
      String? message,
      String? logId,
      AsrResultStructure? resultStructure,
      required bool success,
    }) => AsrTranscribeStats(
      inputBytes: pcm.length,
      inputPeak: gainResult.inputStats.peak,
      inputRms: gainResult.inputStats.rms,
      selectedGain: gainResult.appliedGain,
      gainReason: gainResult.reason,
      outputPeak: gainResult.outputStats.peak,
      outputRms: gainResult.outputStats.rms,
      outputClippingRatio: gainResult.clippingRatio,
      asrStatusCode: statusCode,
      asrMessage: message,
      asrLogId: logId,
      segments: _buildSegments(pcm, asrPcm),
      resultStructure: resultStructure,
      success: success,
    );

    final request = {
      'user': {'uid': 'peilink-physical'},
      'audio': {
        'data': base64Encode(PcmAudioCodec.wavFromPcm(asrPcm)),
        'format': 'wav',
        'codec': 'raw',
        'rate': 16000,
        'bits': 16,
        'channel': 1,
      },
      'request': {
        'model_name': 'bigmodel',
        'enable_itn': true,
        'enable_punc': true,
        if (boostingTableId.trim().isNotEmpty)
          'corpus': {'boosting_table_id': boostingTableId.trim()},
      },
    };
    var response = await _post(
      _submit,
      apiKey,
      requestId,
      utf8.encode(jsonEncode(request)),
    );
    final submitStatus = _status(response);
    if (submitStatus != '20000000') {
      onStats?.call(
        buildStats(
          statusCode: submitStatus,
          message: _safeHeader(response, 'x-api-message') ?? 'ASR 提交失败',
          logId: _safeLogId(response),
          success: false,
        ),
      );
      throw SpeechCloudException('ASR 提交失败（$submitStatus）');
    }
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 1));
      response = await _post(_query, apiKey, requestId, utf8.encode('{}'));
      final status = _status(response);
      if (status == '20000001' || status == '20000002') continue;
      if (status != '20000000') {
        onStats?.call(
          buildStats(
            statusCode: status,
            message: _safeHeader(response, 'x-api-message') ?? 'ASR 查询失败',
            logId: _safeLogId(response),
            success: false,
          ),
        );
        throw SpeechCloudException('ASR 查询失败（$status）');
      }
      final payload = _decodeObject(response.bodyBytes);
      final result = payload['result'];
      final text = result is Map ? result['text']?.toString().trim() ?? '' : '';
      final resultStructure = _readResultStructure(result);
      if (text.isEmpty) {
        onStats?.call(
          buildStats(
            statusCode: status,
            message: _safeHeader(response, 'x-api-message') ?? 'ASR 返回空文本',
            logId: _safeLogId(response),
            resultStructure: resultStructure,
            success: false,
          ),
        );
        throw const SpeechCloudException('ASR 返回空文本');
      }
      onStats?.call(
        buildStats(
          statusCode: status,
          message: _safeHeader(response, 'x-api-message') ?? 'ASR 识别成功',
          logId: _safeLogId(response),
          resultStructure: resultStructure,
          success: true,
        ),
      );
      return text;
    }
    onStats?.call(
      buildStats(statusCode: 'timeout', message: 'ASR 查询超时', success: false),
    );
    throw const SpeechCloudException('ASR 查询超时，未自动重新提交');
  }

  Future<http.Response> _post(
    Uri uri,
    String apiKey,
    String requestId,
    List<int> body,
  ) async {
    final response = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'X-Api-Key': apiKey,
            'X-Api-Resource-Id': _resource,
            'X-Api-Request-Id': requestId,
            'X-Api-Sequence': '-1',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw SpeechCloudException('ASR HTTP ${response.statusCode}');
    }
    return response;
  }

  String _status(http.Response response) =>
      response.headers['x-api-status-code'] ?? 'missing';

  String? _safeHeader(http.Response response, String name) {
    final value = response.headers[name]?.trim();
    if (value == null || value.isEmpty) return null;
    final sanitized = value.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ');
    return sanitized.length <= 160 ? sanitized : sanitized.substring(0, 160);
  }

  String? _safeLogId(http.Response response) {
    final value = _safeHeader(response, 'x-tt-logid');
    if (value == null) return null;
    final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9._:-]'), '');
    if (sanitized.isEmpty) return null;
    return sanitized.length <= 128 ? sanitized : sanitized.substring(0, 128);
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}

AsrResultStructure _readResultStructure(Object? result) {
  if (result is! Map) {
    return const AsrResultStructure(resultTextLength: 0, utterances: []);
  }
  final utterancesValue = result['utterances'];
  final utterances = <AsrUtteranceStructure>[];
  if (utterancesValue is List) {
    for (final value in utterancesValue) {
      if (value is! Map) continue;
      utterances.add(
        AsrUtteranceStructure(
          textLength: value['text']?.toString().length ?? 0,
          startTime: _readTime(value, 'start_time', 'startTime'),
          endTime: _readTime(value, 'end_time', 'endTime'),
        ),
      );
    }
  }
  return AsrResultStructure(
    resultTextLength: result['text']?.toString().trim().length ?? 0,
    utterances: List.unmodifiable(utterances),
  );
}

num? _readTime(Map<dynamic, dynamic> value, String snakeKey, String camelKey) {
  final raw = value[snakeKey] ?? value[camelKey];
  return raw is num ? raw : num.tryParse(raw?.toString() ?? '');
}

class DoubaoTtsClient {
  DoubaoTtsClient({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;
  final http.Client _client;
  final bool _ownsClient;
  static final _endpoint = Uri.parse(
    'https://openspeech.bytedance.com/api/v3/tts/unidirectional/sse',
  );
  static const resourceId = 'seed-tts-2.0';
  static const speaker = 'zh_male_aojiaobazong_uranus_bigtts';

  Future<Uint8List> synthesize({
    required String text,
    required String apiKey,
  }) async {
    final request = http.Request('POST', _endpoint)
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        'X-Api-Key': apiKey,
        'X-Api-Resource-Id': resourceId,
        'X-Api-Request-Id': _uuid(),
      })
      ..body = jsonEncode({
        'user': {'uid': 'peilink-physical'},
        'req_params': {
          'text': text,
          'speaker': speaker,
          'audio_params': {
            'format': 'pcm',
            'sample_rate': 24000,
            'speech_rate': 0,
            'loudness_rate': 0,
          },
        },
      });
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw SpeechCloudException('TTS HTTP ${response.statusCode}');
    }
    final chunks = <int>[];
    await for (final line
        in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (!line.startsWith('data:')) continue;
      final event = jsonDecode(line.substring(5).trim());
      if (event is! Map) throw const SpeechCloudException('TTS SSE 数据无效');
      final code = event['code'] ?? 0;
      if (code != 0 && code != 20000000) {
        throw SpeechCloudException('TTS 失败（$code）');
      }
      final encoded = event['data']?.toString() ?? '';
      if (encoded.isEmpty) continue;
      chunks.addAll(base64Decode(encoded));
      if (chunks.length > PcmAudioCodec.maxPlaybackBytes * 3 ~/ 2) {
        throw const SpeechCloudException('TTS 音频超过 Phase 9 上限');
      }
    }
    if (chunks.isEmpty) throw const SpeechCloudException('TTS 没有返回音频');
    final pcm = Uint8List.fromList(chunks);
    PcmAudioCodec.validatePcm(
      pcm,
      maximum: PcmAudioCodec.maxPlaybackBytes * 3 ~/ 2,
    );
    return pcm;
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}

Map<String, dynamic> _decodeObject(List<int> body) {
  try {
    final value = jsonDecode(utf8.decode(body));
    if (value is Map<String, dynamic>) return value;
  } catch (_) {}
  throw const SpeechCloudException('语音服务返回了无效 JSON');
}

List<AsrTranscribeSegment> _buildSegments(
  Uint8List inputPcm,
  Uint8List outputPcm,
) {
  // Both buffers are produced from the same recording and must have matching
  // sample counts. Keep this guard local so stats can never pair unlike ranges.
  if (inputPcm.length != outputPcm.length) {
    throw StateError('ASR input/output PCM 长度不一致');
  }
  PcmAudioCodec.validatePcm(
    inputPcm,
    maximum: PcmAudioCodec.maxPlaybackBytes * 3 ~/ 2,
  );
  PcmAudioCodec.validatePcm(
    outputPcm,
    maximum: PcmAudioCodec.maxPlaybackBytes * 3 ~/ 2,
  );
  final samples = inputPcm.length ~/ 2;
  final segmentSamples = PcmAudioCodec.sampleRate;
  final count = (samples + segmentSamples - 1) ~/ segmentSamples;
  final segments = <AsrTranscribeSegment>[];
  for (var index = 0; index < count; index++) {
    final start = index * segmentSamples;
    final end = min(samples, start + segmentSamples);
    final startByte = start * 2;
    final endByte = end * 2;
    final inputStats = PcmAudioCodec.stats(
      Uint8List.sublistView(inputPcm, startByte, endByte),
    );
    final outputStats = PcmAudioCodec.stats(
      Uint8List.sublistView(outputPcm, startByte, endByte),
    );
    segments.add(
      AsrTranscribeSegment(
        startSecond: start / PcmAudioCodec.sampleRate,
        endSecond: end / PcmAudioCodec.sampleRate,
        inputPeak: inputStats.peak,
        inputRms: inputStats.rms,
        outputPeak: outputStats.peak,
        outputRms: outputStats.rms,
      ),
    );
  }
  return List.unmodifiable(segments);
}

String _uuid() {
  final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class SpeechCloudException implements Exception {
  const SpeechCloudException(this.message);
  final String message;
  @override
  String toString() => message;
}
