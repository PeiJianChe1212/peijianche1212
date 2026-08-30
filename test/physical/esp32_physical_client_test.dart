import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:peijianche_app/physical/esp32_physical_client.dart';

void main() {
  test('rejects public destinations before sending a request', () async {
    var called = false;
    final client = Esp32PhysicalClient(
      client: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      client.status(host: 'example.com', key: 'secret'),
      throwsA(isA<FormatException>()),
    );
    expect(called, isFalse);
  });

  test('accepts only a healthy idle Phase 9 status', () async {
    final client = Esp32PhysicalClient(
      client: MockClient((request) async {
        expect(request.url.toString(), 'http://192.168.2.215:8080/status');
        expect(request.headers['X-PeiLink-Key'], 'secret');
        return http.Response(
          jsonEncode({
            'ok': true,
            'phase': 9,
            'state': 'idle',
            'sample_rate': 16000,
            'bits': 16,
            'channels': 1,
            'record_seconds': 8,
            'max_playback_bytes': 1048576,
            'rx_errors': 0,
            'tx_errors': 0,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    expect(
      (await client.status(host: '192.168.2.215', key: 'secret')).phase,
      9,
    );
  });

  test('never follows a device redirect', () async {
    var calls = 0;
    final client = Esp32PhysicalClient(
      client: MockClient((request) async {
        calls++;
        expect(request.followRedirects, isFalse);
        return http.Response(
          '',
          302,
          headers: {'location': 'http://192.168.2.99:8080/status'},
        );
      }),
    );
    await expectLater(
      client.status(host: '192.168.2.215', key: 'secret'),
      throwsA(isA<PhysicalProtocolException>()),
    );
    expect(calls, 1);
  });
}
