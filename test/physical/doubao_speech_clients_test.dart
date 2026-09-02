import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:peijianche_app/physical/doubao_speech_clients.dart';
import 'package:peijianche_app/physical/pcm_audio_codec.dart';
import 'package:peijianche_app/physical/pcm_audio_gain.dart';

void main() {
  test(
    'ASR sends V3 headers, WAV audio and the optional boosting table',
    () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        expect(request.headers['X-Api-Key'], 'private-key');
        expect(request.headers['X-Api-Resource-Id'], 'volc.seedasr.auc');
        if (calls == 1) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final audio = body['audio'] as Map<String, dynamic>;
          expect(
            base64Decode(audio['data'] as String).take(4),
            'RIFF'.codeUnits,
          );
          final requestData = body['request'] as Map<String, dynamic>;
          expect(
            (requestData['corpus'] as Map)['boosting_table_id'],
            'table-id',
          );
          return http.Response(
            '{}',
            200,
            headers: {'x-api-status-code': '20000000'},
          );
        }
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'result': {'text': '裴简澈，你好'},
            }),
          ),
          200,
          headers: {'x-api-status-code': '20000000'},
        );
      });
      final asr = DoubaoAsrClient(client: client);
      final text = await asr.transcribe(
        pcm: Uint8List(PcmAudioCodec.recordBytes),
        apiKey: 'private-key',
        boostingTableId: 'table-id',
      );
      expect(text, '裴简澈，你好');
      expect(calls, 2);
    },
  );

  test(
    'ASR onStats returns desensitized stats matching the actual uploaded copy',
    () async {
      var calls = 0;
      Uint8List? uploadedWav;
      final client = MockClient((request) async {
        calls++;
        if (calls == 1) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final audio = body['audio'] as Map<String, dynamic>;
          uploadedWav = base64Decode(audio['data'] as String);
          return http.Response(
            '{}',
            200,
            headers: {
              'x-api-status-code': '20000000',
              'x-api-message': 'OK',
              'x-tt-logid': 'test-logid-123',
            },
          );
        }
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'result': {'text': '统计测试'},
            }),
          ),
          200,
          headers: {
            'x-api-status-code': '20000000',
            'x-api-message': 'OK',
            'x-tt-logid': 'test-logid-123',
          },
        );
      });

      // 构造一个已知低电平 PCM（RMS 约 100，会触发增益）
      final pcm = _buildLowLevelPcm(samples: 16000, amplitude: 200);
      final inputHash = _hashBytes(pcm);
      final inputStats = PcmAudioCodec.stats(pcm);

      AsrTranscribeStats? captured;
      final asr = DoubaoAsrClient(client: client);
      final text = await asr.transcribe(
        pcm: pcm,
        apiKey: 'private-key',
        onStats: (stats) => captured = stats,
      );

      expect(text, '统计测试');
      expect(calls, 2);
      expect(captured, isNotNull);

      // 输入统计与原始 PCM 一致
      expect(captured!.inputBytes, pcm.length);
      expect(captured!.inputPeak, inputStats.peak);
      expect(captured!.inputRms, closeTo(inputStats.rms, 0.1));

      // 增益已应用（低电平输入）
      expect(captured!.selectedGain, greaterThan(1.0));
      expect(captured!.gainReason, GainReason.lowLevelBoosted);

      // 输出统计与实际上传的 WAV 中的 PCM 一致
      expect(uploadedWav, isNotNull);
      // WAV 头部 44 字节，后面是 PCM 数据
      final uploadedPcm = Uint8List.sublistView(uploadedWav!, 44);
      final uploadedStats = PcmAudioCodec.stats(uploadedPcm);
      expect(captured!.outputPeak, uploadedStats.peak);
      expect(captured!.outputRms, closeTo(uploadedStats.rms, 0.1));

      // 削波比例合理
      expect(captured!.outputClippingRatio, greaterThanOrEqualTo(0.0));
      expect(captured!.outputClippingRatio, lessThan(0.01));

      // ASR 状态
      expect(captured!.asrStatusCode, '20000000');
      expect(captured!.asrMessage, 'OK');
      expect(captured!.asrLogId, 'test-logid-123');
      expect(captured!.success, isTrue);

      // 原始 PCM 未被修改
      expect(_hashBytes(pcm), inputHash);

      // 统计中不包含敏感信息
      expect(captured!.toString(), isNot(contains('private-key')));
      expect(captured!.toString(), isNot(contains('base64')));
    },
  );

  test('ASR onStats also reports stats on submit failure', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response(
        '{}',
        200,
        headers: calls == 1
            ? {'x-api-status-code': '20000000'}
            : {
                'x-api-status-code': '20000003',
                'x-api-message': 'Silent audio',
                'x-tt-logid': 'silent-logid-456',
              },
      );
    });

    final pcm = _buildLowLevelPcm(samples: 16000, amplitude: 200);
    AsrTranscribeStats? captured;
    final asr = DoubaoAsrClient(client: client);

    try {
      await asr.transcribe(
        pcm: pcm,
        apiKey: 'private-key',
        onStats: (stats) => captured = stats,
      );
      fail('should throw');
    } on SpeechCloudException catch (_) {
      // expected
    }

    expect(captured, isNotNull);
    expect(captured!.success, isFalse);
    expect(captured!.asrStatusCode, '20000003');
    expect(captured!.asrMessage, 'Silent audio');
    expect(captured!.asrLogId, 'silent-logid-456');
    expect(captured!.inputBytes, pcm.length);
    expect(captured!.selectedGain, greaterThan(1.0));
  });

  test(
    'ASR stats expose only final result lengths and utterance times',
    () async {
      var calls = 0;
      const sensitiveResultText = '不能进入统计的完整结果';
      const sensitiveUtteranceText = '不能进入统计的分句';
      final client = MockClient((_) async {
        calls++;
        return http.Response.bytes(
          utf8.encode(
            calls == 1
                ? '{}'
                : jsonEncode({
                    'result': {
                      'text': sensitiveResultText,
                      'utterances': [
                        {
                          'text': sensitiveUtteranceText,
                          'start_time': 120,
                          'end_time': 980,
                        },
                        {'text': '第二句', 'startTime': 1000, 'endTime': 1500},
                      ],
                    },
                  }),
          ),
          200,
          headers: {'x-api-status-code': '20000000'},
        );
      });
      AsrTranscribeStats? captured;
      final transcript = await DoubaoAsrClient(client: client).transcribe(
        pcm: _buildLowLevelPcm(samples: 16000, amplitude: 200),
        apiKey: 'private-key',
        onStats: (stats) => captured = stats,
      );

      expect(transcript, sensitiveResultText);
      final structure = captured!.resultStructure!;
      expect(structure.resultTextLength, sensitiveResultText.length);
      expect(structure.utteranceCount, 2);
      expect(structure.utterances[0].textLength, sensitiveUtteranceText.length);
      expect(structure.utterances[0].startTime, 120);
      expect(structure.utterances[0].endTime, 980);
      expect(structure.utterances[1].textLength, 3);
      expect(structure.utterances[1].startTime, 1000);
      expect(structure.utterances[1].endTime, 1500);
      expect(captured.toString(), isNot(contains(sensitiveResultText)));
      expect(captured.toString(), isNot(contains(sensitiveUtteranceText)));
    },
  );

  test('ASR stats handle a final result without utterances', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response.bytes(
        utf8.encode(calls == 1 ? '{}' : '{"result":{"text":"只有结果"}}'),
        200,
        headers: {'x-api-status-code': '20000000'},
      );
    });
    AsrTranscribeStats? captured;
    await DoubaoAsrClient(client: client).transcribe(
      pcm: _buildLowLevelPcm(samples: 16000, amplitude: 200),
      apiKey: 'key',
      onStats: (stats) => captured = stats,
    );

    expect(captured!.resultStructure!.resultTextLength, 4);
    expect(captured!.resultStructure!.utteranceCount, 0);
  });

  test(
    'ASR stats split the original and uploaded PCM into one-second ranges',
    () async {
      var calls = 0;
      Uint8List? uploadedPcm;
      final client = MockClient((request) async {
        calls++;
        if (calls == 1) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          uploadedPcm = Uint8List.sublistView(
            base64Decode((body['audio'] as Map)['data'] as String),
            44,
          );
          return http.Response(
            '{}',
            200,
            headers: {'x-api-status-code': '20000000'},
          );
        }
        return http.Response.bytes(
          utf8.encode('{"result":{"text":"分段"}}'),
          200,
          headers: {'x-api-status-code': '20000000'},
        );
      });
      final pcm = _buildSegmentedPcm();
      AsrTranscribeStats? captured;
      await DoubaoAsrClient(client: client).transcribe(
        pcm: pcm,
        apiKey: 'key',
        onStats: (stats) => captured = stats,
      );

      expect(captured!.segments, hasLength(2));
      expect(captured!.segments[0].startSecond, 0);
      expect(captured!.segments[0].endSecond, 1);
      expect(captured!.segments[1].startSecond, 1);
      expect(captured!.segments[1].endSecond, 2);
      final uploaded = uploadedPcm!;
      for (var index = 0; index < 2; index++) {
        final start = index * PcmAudioCodec.sampleRate * 2;
        final end = (index + 1) * PcmAudioCodec.sampleRate * 2;
        final inputStats = PcmAudioCodec.stats(
          Uint8List.sublistView(pcm, start, end),
        );
        final outputStats = PcmAudioCodec.stats(
          Uint8List.sublistView(uploaded, start, end),
        );
        final segment = captured!.segments[index];
        expect(segment.inputPeak, inputStats.peak);
        expect(segment.inputRms, closeTo(inputStats.rms, 0.01));
        expect(segment.outputPeak, outputStats.peak);
        expect(segment.outputRms, closeTo(outputStats.rms, 0.01));
      }
    },
  );

  test('eight-second PCM produces eight exact one-second segments', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response.bytes(
        utf8.encode(calls == 1 ? '{}' : '{"result":{"text":"八段"}}'),
        200,
        headers: {'x-api-status-code': '20000000'},
      );
    });
    AsrTranscribeStats? captured;
    await DoubaoAsrClient(client: client).transcribe(
      pcm: _buildLowLevelPcm(
        samples: PcmAudioCodec.sampleRate * 8,
        amplitude: 200,
      ),
      apiKey: 'key',
      onStats: (stats) => captured = stats,
    );
    expect(captured!.segments, hasLength(8));
    expect(captured!.segments.first.startSecond, 0.0);
    expect(captured!.segments.first.endSecond, 1.0);
    expect(captured!.segments.last.startSecond, 7.0);
    expect(captured!.segments.last.endSecond, 8.0);
  });

  test(
    'short valid PCM produces one partial segment and invalid PCM makes no request',
    () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response.bytes(
          utf8.encode(calls == 1 ? '{}' : '{"result":{"text":"短"}}'),
          200,
          headers: {'x-api-status-code': '20000000'},
        );
      });
      AsrTranscribeStats? captured;
      await DoubaoAsrClient(client: client).transcribe(
        pcm: _buildLowLevelPcm(samples: 8000, amplitude: 200),
        apiKey: 'key',
        onStats: (stats) => captured = stats,
      );
      expect(captured!.segments, hasLength(1));
      expect(captured!.segments.single.startSecond, 0);
      expect(captured!.segments.single.endSecond, 0.5);
      expect(calls, 2);

      var invalidCalls = 0;
      final invalidClient = MockClient((_) async {
        invalidCalls++;
        return http.Response('{}', 500);
      });
      await expectLater(
        DoubaoAsrClient(
          client: invalidClient,
        ).transcribe(pcm: Uint8List(3), apiKey: 'key'),
        throwsA(isA<FormatException>()),
      );
      expect(invalidCalls, 0);
    },
  );

  test(
    'ASR already-loud-enough input gets gain 1.0 and stats reflect no boost',
    () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        if (calls == 1) {
          return http.Response(
            '{}',
            200,
            headers: {'x-api-status-code': '20000000'},
          );
        }
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'result': {'text': '大声'},
            }),
          ),
          200,
          headers: {'x-api-status-code': '20000000'},
        );
      });

      // 高电平 PCM（RMS > 1500，不应增益）
      final pcm = _buildLowLevelPcm(samples: 16000, amplitude: 5000);
      AsrTranscribeStats? captured;
      final asr = DoubaoAsrClient(client: client);
      await asr.transcribe(
        pcm: pcm,
        apiKey: 'key',
        onStats: (stats) => captured = stats,
      );

      expect(captured, isNotNull);
      expect(captured!.selectedGain, closeTo(1.0, 0.001));
      expect(captured!.gainReason, GainReason.alreadyLoudEnough);
      expect(captured!.outputPeak, captured!.inputPeak);
      expect(captured!.outputRms, closeTo(captured!.inputRms, 0.1));
    },
  );

  test(
    'TTS requests the accepted voice and concatenates PCM SSE chunks',
    () async {
      final client = MockClient((request) async {
        expect(
          request.headers['X-Api-Resource-Id'],
          DoubaoTtsClient.resourceId,
        );
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final params = body['req_params'] as Map<String, dynamic>;
        expect(params['speaker'], DoubaoTtsClient.speaker);
        expect((params['audio_params'] as Map)['sample_rate'], 24000);
        final event = jsonEncode({
          'code': 20000000,
          'data': base64Encode([1, 0, 2, 0]),
        });
        return http.Response(
          'data: $event\n\n',
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
      final tts = DoubaoTtsClient(client: client);
      expect(await tts.synthesize(text: '测试', apiKey: 'private-key'), [
        1,
        0,
        2,
        0,
      ]);
    },
  );
}

/// 构造一个指定幅度的正弦波 PCM（16-bit mono, 16kHz）。
Uint8List _buildLowLevelPcm({required int samples, required int amplitude}) {
  final pcm = Uint8List(samples * 2);
  final data = ByteData.sublistView(pcm);
  for (var i = 0; i < samples; i++) {
    final sample = (amplitude * (i % 100 < 50 ? 1.0 : -1.0)).round();
    data.setInt16(i * 2, sample, Endian.little);
  }
  return pcm;
}

Uint8List _buildSegmentedPcm() {
  const samplesPerSegment = PcmAudioCodec.sampleRate;
  final pcm = Uint8List(samplesPerSegment * 2 * 2);
  final data = ByteData.sublistView(pcm);
  for (var i = 0; i < samplesPerSegment * 2; i++) {
    final amplitude = i < samplesPerSegment ? 100 : 500;
    data.setInt16(i * 2, amplitude, Endian.little);
  }
  return pcm;
}

/// 简单的字节哈希，用于验证原始 PCM 未被修改。
int _hashBytes(Uint8List bytes) {
  var hash = 0;
  for (final b in bytes) {
    hash = (hash * 31 + b) & 0x7fffffff;
  }
  return hash;
}
