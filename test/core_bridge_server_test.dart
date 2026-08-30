import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/services/core_bridge_server.dart';

void main() {
  const token = 'test-bridge-token';

  Future<int> unusedPort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  Future<(int, Map<String, dynamic>)> post(
    int port, {
    String? authorization = 'Bearer $token',
    String? origin,
    Map<String, Object> body = const {
      'requestId': 'request-1',
      'characterId': 'character-1',
      'userText': '你好',
    },
  }) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:$port/v1/chat/reply'),
      );
      request.headers.contentType = ContentType.json;
      if (authorization != null) {
        request.headers.set(HttpHeaders.authorizationHeader, authorization);
      }
      if (origin != null) request.headers.set('origin', origin);
      request.write(jsonEncode(body));
      final response = await request.close();
      final decoded = jsonDecode(await utf8.decoder.bind(response).join());
      return (response.statusCode, Map<String, dynamic>.from(decoded as Map));
    } finally {
      client.close(force: true);
    }
  }

  test('default closed server does not listen on a port', () async {
    final port = await unusedPort();
    final server = CoreBridgeServer(
      handler: ({required characterId, required userText}) async => 'unused',
    );
    addTearDown(server.dispose);

    expect(server.isRunning, isFalse);
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    await expectLater(
      client.getUrl(Uri.parse('http://127.0.0.1:$port/v1/chat/reply')),
      throwsA(isA<SocketException>()),
    );
  });

  test('enabled server binds only IPv4 loopback and rejects missing token', () async {
    final server = CoreBridgeServer(
      handler: ({required characterId, required userText}) async => '回复',
    );
    addTearDown(server.dispose);
    await server.start(token: token, port: 0);

    expect(server.boundAddress, InternetAddress.loopbackIPv4);
    final (status, body) = await post(
      server.boundPort!,
      authorization: null,
    );
    expect(status, 401);
    expect((body['error'] as Map)['code'], 'UNAUTHORIZED');
  });

  test('wrong token and browser origin are rejected without calling Core', () async {
    var calls = 0;
    final server = CoreBridgeServer(
      handler: ({required characterId, required userText}) async {
        calls++;
        return '不应调用';
      },
    );
    addTearDown(server.dispose);
    await server.start(token: token, port: 0);

    expect(
      (await post(server.boundPort!, authorization: 'Bearer wrong')).$1,
      401,
    );
    expect(
      (await post(server.boundPort!, origin: 'http://example.test')).$1,
      403,
    );
    expect(calls, 0);
  });

  test('test provider maps characterId and userText to reply', () async {
    final server = CoreBridgeServer(
      handler: ({required characterId, required userText}) async {
        expect(characterId, 'pei');
        expect(userText, '今天好吗');
        return '我很好。';
      },
    );
    addTearDown(server.dispose);
    await server.start(token: token, port: 0);

    final (status, body) = await post(
      server.boundPort!,
      body: const {
        'requestId': 'physical-1',
        'characterId': 'pei',
        'userText': '今天好吗',
      },
    );
    expect(status, 200);
    expect(body, {'requestId': 'physical-1', 'reply': '我很好。'});
  });

  test('requests execute strictly serially', () async {
    var active = 0;
    var maxActive = 0;
    final firstEntered = Completer<void>();
    final releaseFirst = Completer<void>();
    final server = CoreBridgeServer(
      handler: ({required characterId, required userText}) async {
        active++;
        if (active > maxActive) maxActive = active;
        if (userText == 'first') {
          firstEntered.complete();
          await releaseFirst.future;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
        active--;
        return userText;
      },
    );
    addTearDown(server.dispose);
    await server.start(token: token, port: 0);

    final first = post(
      server.boundPort!,
      body: const {
        'requestId': 'serial-1',
        'characterId': 'pei',
        'userText': 'first',
      },
    );
    await firstEntered.future;
    final second = post(
      server.boundPort!,
      body: const {
        'requestId': 'serial-2',
        'characterId': 'pei',
        'userText': 'second',
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(maxActive, 1);
    releaseFirst.complete();
    await Future.wait([first, second]);
    expect(maxActive, 1);
  });

  test('requestId result is cached and conflicting reuse is rejected', () async {
    var calls = 0;
    final server = CoreBridgeServer(
      handler: ({required characterId, required userText}) async {
        calls++;
        return 'reply-$calls';
      },
    );
    addTearDown(server.dispose);
    await server.start(token: token, port: 0);

    final first = await post(server.boundPort!);
    final duplicate = await post(server.boundPort!);
    final conflict = await post(
      server.boundPort!,
      body: const {
        'requestId': 'request-1',
        'characterId': 'character-1',
        'userText': '不同内容',
      },
    );
    expect(first.$2['reply'], 'reply-1');
    expect(duplicate.$2['reply'], 'reply-1');
    expect(conflict.$1, 409);
    expect(calls, 1);
  });
}
