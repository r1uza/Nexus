import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'config.dart';
import 'errors.dart';
import 'json_support.dart';
import 'model.dart';
import 'runtime.dart';

final class NexusHttpService {
  NexusHttpService({required this.runtime, required this.config});

  final NexusRuntime runtime;
  final NexusConfig config;
  HttpServer? _server;
  StreamSubscription<HttpRequest>? _subscription;

  int get port => _server?.port ?? config.port;

  Future<int> start() async {
    if (_server != null) {
      throw const NexusException('already_started', 'HTTP service is running');
    }
    final server = await HttpServer.bind(config.bindAddress, config.port);
    _server = server;
    _subscription = server.listen(
      (HttpRequest request) => unawaited(_handleSafely(request)),
      onError: (Object _) {},
      cancelOnError: false,
    );
    return server.port;
  }

  Future<void> close() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _handleSafely(HttpRequest request) async {
    try {
      await _handle(request);
    } on NexusException catch (error) {
      await _json(request.response, error.statusCode, <String, Object?>{
        'error': <String, Object?>{
          'code': error.code,
          'message': error.message,
        },
      });
    } on FormatException {
      await _json(request.response, HttpStatus.badRequest, <String, Object?>{
        'error': <String, Object?>{
          'code': 'invalid_json',
          'message': 'Request body is not valid JSON',
        },
      });
    } on Object {
      await _json(
        request.response,
        HttpStatus.internalServerError,
        <String, Object?>{
          'error': <String, Object?>{
            'code': 'internal_error',
            'message': 'Request failed without a safe result',
          },
        },
      );
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final method = request.method;
    final path = request.uri.path;
    if (method == 'GET' && path == '/healthz') {
      await _json(request.response, HttpStatus.ok, <String, Object?>{
        'status': 'ok',
        'service': 'NEXUS.sf',
      });
      return;
    }
    if (method == 'GET' && path == '/v1/status') {
      await _json(request.response, HttpStatus.ok, runtime.status());
      return;
    }
    _requireAdmin(request);

    if (method == 'GET' && path == '/v1/nodes') {
      await _json(request.response, HttpStatus.ok, <String, Object?>{
        'nodes': runtime.registry.nodes
            .map((NodeDefinition node) => node.toJson())
            .toList(),
      });
      return;
    }
    if (method == 'GET' && path == '/v1/traces') {
      final requested = int.tryParse(
        request.uri.queryParameters['limit'] ?? '100',
      );
      if (requested == null || requested < 1 || requested > 1000) {
        throw const NexusException(
          'invalid_limit',
          'Trace limit must be between 1 and 1000',
        );
      }
      await _json(request.response, HttpStatus.ok, <String, Object?>{
        'traces': runtime.traceSink
            .recent(limit: requested)
            .map((TraceRecord record) => record.toJson())
            .toList(),
      });
      return;
    }
    if (method == 'POST' && path == '/v1/nodes') {
      final body = await _readJson(request);
      final node = NodeDefinition.fromJson(body);
      if (node.transport != TransportKind.http) {
        throw const NexusException(
          'external_transport_required',
          'The HTTP API can register only HTTP nodes',
        );
      }
      runtime.registry.register(node);
      await _json(request.response, HttpStatus.created, node.toJson());
      return;
    }
    if (method == 'DELETE' &&
        request.uri.pathSegments.length == 3 &&
        request.uri.pathSegments[0] == 'v1' &&
        request.uri.pathSegments[1] == 'nodes') {
      final id = request.uri.pathSegments[2];
      validateIdentifier(id, 'nodeId');
      final removed = runtime.registry.remove(id);
      if (!removed) {
        throw NexusException(
          'node_not_found',
          'Node not found: $id',
          statusCode: HttpStatus.notFound,
        );
      }
      await _json(request.response, HttpStatus.ok, <String, Object?>{
        'removed': id,
      });
      return;
    }
    if (method == 'POST' && path == '/v1/authorizations') {
      final body = await _readJson(request);
      final ttlSeconds = optionalInt(body, 'ttlSeconds') ?? 60;
      final authorization = runtime.authorization.issue(
        subject: requireString(body, 'subject', maxLength: 128),
        capability: requireString(body, 'capability', maxLength: 128),
        targetNode: optionalString(body, 'targetNode', maxLength: 128),
        ttl: Duration(seconds: ttlSeconds),
      );
      await _json(request.response, HttpStatus.created, authorization.toJson());
      return;
    }
    if (method == 'POST' && path == '/v1/dispatch') {
      final result = await runtime.dispatch(
        DispatchRequest.fromJson(await _readJson(request)),
      );
      await _json(request.response, result.httpStatus, result.toJson());
      return;
    }
    throw const NexusException(
      'route_not_found',
      'HTTP route not found',
      statusCode: HttpStatus.notFound,
    );
  }

  void _requireAdmin(HttpRequest request) {
    final authorization = request.headers.value(
      HttpHeaders.authorizationHeader,
    );
    if (authorization == null || !authorization.startsWith('Bearer ')) {
      throw const NexusException(
        'admin_auth_required',
        'A bearer token is required',
        statusCode: HttpStatus.unauthorized,
      );
    }
    final candidate = authorization.substring('Bearer '.length);
    if (!_constantTimeEquals(candidate, config.adminToken)) {
      throw const NexusException(
        'admin_auth_invalid',
        'Bearer token is invalid',
        statusCode: HttpStatus.unauthorized,
      );
    }
  }

  Future<Map<String, Object?>> _readJson(HttpRequest request) async {
    final contentType = request.headers.contentType;
    if (contentType?.mimeType != 'application/json') {
      throw const NexusException(
        'content_type_required',
        'Content-Type must be application/json',
        statusCode: HttpStatus.unsupportedMediaType,
      );
    }
    if (request.contentLength > config.maxBodyBytes) {
      throw const NexusException(
        'request_too_large',
        'Request body exceeds the configured limit',
        statusCode: HttpStatus.requestEntityTooLarge,
      );
    }
    final bytes = <int>[];
    await for (final chunk in request) {
      bytes.addAll(chunk);
      if (bytes.length > config.maxBodyBytes) {
        throw const NexusException(
          'request_too_large',
          'Request body exceeds the configured limit',
          statusCode: HttpStatus.requestEntityTooLarge,
        );
      }
    }
    if (bytes.isEmpty) {
      throw const NexusException('body_required', 'A JSON body is required');
    }
    final Object? decoded = jsonDecode(utf8.decode(bytes));
    return requireObject(decoded, 'request body');
  }

  Future<void> _json(
    HttpResponse response,
    int status,
    Map<String, Object?> body,
  ) async {
    response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..headers.set('X-Content-Type-Options', 'nosniff')
      ..headers.set('Cache-Control', 'no-store')
      ..headers.set('Referrer-Policy', 'no-referrer')
      ..write(jsonEncode(body));
    await response.close();
  }
}

bool _constantTimeEquals(String left, String right) {
  final leftBytes = utf8.encode(left);
  final rightBytes = utf8.encode(right);
  var difference = leftBytes.length ^ rightBytes.length;
  final length = leftBytes.length > rightBytes.length
      ? leftBytes.length
      : rightBytes.length;
  for (var index = 0; index < length; index += 1) {
    final leftByte = index < leftBytes.length ? leftBytes[index] : 0;
    final rightByte = index < rightBytes.length ? rightBytes[index] : 0;
    difference |= leftByte ^ rightByte;
  }
  return difference == 0;
}
