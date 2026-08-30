import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:peijianche_app/physical/doubao_speech_clients.dart';
import 'package:peijianche_app/physical/pcm_audio_codec.dart';

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
