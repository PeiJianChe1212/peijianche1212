import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'core_bridge_config_service.dart';
import 'core_bridge_service.dart';

typedef CoreBridgeHandler = Future<String> Function({
  required String characterId,
  required String userText,
});

class CoreBridgeServer {
  CoreBridgeServer({CoreBridgeHandler? handler})
    : _service = handler == null ? CoreBridgeService() : null,
      _handler = handler;

  static const int maxBodyBytes = 16 * 1024;
  static const int maxUserTextLength = 8000;
  static const int maxRequestIdLength = 128;

  final CoreBridgeService? _service;
  final CoreBridgeHandler? _handler;
  final Map<String, _CachedReply> _cache = {};
  HttpServer? _server;
  Future<void> _serialTail = Future<void>.value();
  String _token = '';

  bool get isRunning => _server != null;
  int? get boundPort => _server?.port;
  InternetAddress? get boundAddress => _server?.address;

  Future<void> start({
    required String token,
    int port = CoreBridgeConfigService.port,
  }) async {
    if (_server != null) return;
    if (token.trim().isEmpty) {
      throw StateError('Bridge Token 不能为空');
    }
    _token = token;
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      port,
      shared: false,
    );
    _server = server;
    unawaited(_serve(server));
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      unawaited(_handleRequest(request));
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.method != 'POST' || request.uri.path != '/v1/chat/reply') {
        return _error(request.response, 404, '', 'NOT_FOUND', '接口不存在');
      }
      if (request.headers.value('origin') != null) {
        return _error(request.response, 403, '', 'ORIGIN_REJECTED', '不接受浏览器来源请求');
      }
      final contentType = request.headers.contentType;
      if (contentType?.mimeType != ContentType.json.mimeType) {
        return _error(
          request.response,
          415,
          '',
          'INVALID_CONTENT_TYPE',
          '仅接受 application/json',
        );
      }
      if (!_authorized(request.headers.value(HttpHeaders.authorizationHeader))) {
        return _error(request.response, 401, '', 'UNAUTHORIZED', 'Bridge Token 无效');
      }
      final bytes = <int>[];
      await for (final chunk in request) {
        bytes.addAll(chunk);
        if (bytes.length > maxBodyBytes) {
          return _error(
            request.response,
            413,
            '',
            'REQUEST_TOO_LARGE',
            '请求内容过大',
          );
        }
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) {
        return _error(request.response, 400, '', 'INVALID_REQUEST', '请求格式无效');
      }
      final requestId = decoded['requestId']?.toString().trim() ?? '';
      final characterId = decoded['characterId']?.toString().trim() ?? '';
      final userText = decoded['userText']?.toString().trim() ?? '';
      if (requestId.isEmpty ||
          requestId.length > maxRequestIdLength ||
          characterId.isEmpty ||
          userText.isEmpty ||
          userText.length > maxUserTextLength) {
        return _error(request.response, 400, requestId, 'INVALID_REQUEST', '请求参数无效');
      }

      final fingerprint = sha256
          .convert(utf8.encode('$characterId\u0000$userText'))
          .toString();
      final cached = _cache[requestId];
      if (cached != null) {
        if (cached.fingerprint != fingerprint) {
          return _error(
            request.response,
            409,
            requestId,
            'REQUEST_ID_CONFLICT',
            'requestId 已用于其他请求',
          );
        }
        return _success(request.response, requestId, cached.reply);
      }

      final completer = Completer<String>();
      _serialTail = _serialTail.then((_) async {
        try {
          completer.complete(
            await (_handler ?? _service!.reply)(
              characterId: characterId,
              userText: userText,
            ),
          );
        } catch (error, stackTrace) {
          completer.completeError(error, stackTrace);
        }
      });
      final reply = await completer.future.timeout(const Duration(seconds: 90));
      _cache[requestId] = _CachedReply(fingerprint, reply);
      while (_cache.length > 100) {
        _cache.remove(_cache.keys.first);
      }
      return _success(request.response, requestId, reply);
    } on CoreBridgeException catch (error) {
      return _error(
        request.response,
        error.statusCode,
        '',
        error.code,
        error.message,
      );
    } on TimeoutException {
      return _error(request.response, 504, '', 'REQUEST_TIMEOUT', 'Core 请求超时');
    } on FormatException {
      return _error(request.response, 400, '', 'INVALID_REQUEST', '请求格式无效');
    } catch (_) {
      return _error(request.response, 500, '', 'CORE_UNAVAILABLE', 'PeiLink Core 暂时不可用');
    }
  }

  bool _authorized(String? authorization) {
    const prefix = 'Bearer ';
    if (authorization == null || !authorization.startsWith(prefix)) return false;
    final supplied = authorization.substring(prefix.length);
    final expectedBytes = utf8.encode(_token);
    final suppliedBytes = utf8.encode(supplied);
    if (expectedBytes.length != suppliedBytes.length) return false;
    var difference = 0;
    for (var index = 0; index < expectedBytes.length; index++) {
      difference |= expectedBytes[index] ^ suppliedBytes[index];
    }
    return difference == 0;
  }

  Future<void> _success(HttpResponse response, String requestId, String reply) =>
      _json(response, 200, {'requestId': requestId, 'reply': reply});

  Future<void> _error(
    HttpResponse response,
    int status,
    String requestId,
    String code,
    String message,
  ) => _json(response, status, {
    'requestId': requestId,
    'error': {'code': code, 'message': message},
  });

  Future<void> _json(
    HttpResponse response,
    int status,
    Map<String, Object> body,
  ) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.headers.set('Cache-Control', 'no-store');
    response.write(jsonEncode(body));
    await response.close();
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    if (server != null) await server.close(force: true);
  }

  Future<void> dispose() async {
    await stop();
    _service?.dispose();
  }
}

class _CachedReply {
  const _CachedReply(this.fingerprint, this.reply);

  final String fingerprint;
  final String reply;
}
