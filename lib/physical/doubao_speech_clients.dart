import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'pcm_audio_codec.dart';

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
  }) async {
    final requestId = _uuid();
    final request = {
      'user': {'uid': 'peilink-physical'},
      'audio': {
        'data': base64Encode(PcmAudioCodec.wavFromPcm(pcm)),
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
    if (_status(response) != '20000000') {
      throw SpeechCloudException('ASR 提交失败（${_status(response)}）');
    }
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 1));
      response = await _post(_query, apiKey, requestId, utf8.encode('{}'));
      final status = _status(response);
      if (status == '20000001' || status == '20000002') continue;
      if (status != '20000000') throw SpeechCloudException('ASR 查询失败（$status）');
      final payload = _decodeObject(response.bodyBytes);
      final result = payload['result'];
      final text = result is Map ? result['text']?.toString().trim() ?? '' : '';
      if (text.isEmpty) throw const SpeechCloudException('ASR 返回空文本');
      return text;
    }
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
  void dispose() {
    if (_ownsClient) _client.close();
  }
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
