import 'dart:convert';
import 'dart:io';

import 'errors.dart';
import 'json_support.dart';
import 'model.dart';
import 'ports.dart';
import 'registry.dart';

final class LocalTransport implements NexusTransport {
  final Map<String, LocalNodeHandler> _handlers = <String, LocalNodeHandler>{};

  void register(String nodeId, LocalNodeHandler handler) {
    _handlers[nodeId] = handler;
  }

  @override
  Future<Map<String, Object?>> deliver(
    NodeDefinition node,
    DispatchContext context,
    Map<String, Object?> payload,
  ) async {
    final handler = _handlers[node.id];
    if (handler == null) {
      throw NexusException(
        'local_handler_missing',
        'No local handler is registered for ${node.id}',
      );
    }
    return handler(context, payload);
  }
}

final class HttpNodeTransport implements NexusTransport {
  HttpNodeTransport({
    required this.endpointPolicy,
    required this.maxResponseBytes,
  });

  final EndpointPolicy endpointPolicy;
  final int maxResponseBytes;

  @override
  Future<Map<String, Object?>> deliver(
    NodeDefinition node,
    DispatchContext context,
    Map<String, Object?> payload,
  ) async {
    final endpoint = node.endpoint;
    if (endpoint == null) {
      throw const NexusException(
        'endpoint_missing',
        'HTTP endpoint is missing',
      );
    }
    endpointPolicy.validate(endpoint);
    final client = HttpClient()..userAgent = 'NEXUS.sf/1.0.0';
    try {
      final request = await client.postUrl(endpoint);
      request
        ..followRedirects = false
        ..maxRedirects = 0
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(<String, Object?>{
            'protocol': 'nexus.sf/1.0',
            'correlationId': context.correlationId,
            'capability': context.capability,
            'targetNode': context.nodeId,
            'payload': payload,
          }),
        );
      final response = await request.close();
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > maxResponseBytes) {
          throw const NexusException(
            'response_too_large',
            'Downstream response exceeds the configured limit',
          );
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw NexusException(
          'downstream_status',
          'Downstream returned HTTP ${response.statusCode}',
        );
      }
      if (bytes.isEmpty) return <String, Object?>{};
      final Object? decoded;
      try {
        decoded = jsonDecode(utf8.decode(bytes));
      } on FormatException {
        throw const NexusException(
          'downstream_json_invalid',
          'Downstream response is not valid JSON',
        );
      }
      return requireObject(decoded, 'downstream response');
    } finally {
      client.close(force: true);
    }
  }
}

final class TransportRouter implements NexusTransport {
  TransportRouter({required this.local, required this.http});

  final LocalTransport local;
  final HttpNodeTransport http;

  @override
  Future<Map<String, Object?>> deliver(
    NodeDefinition node,
    DispatchContext context,
    Map<String, Object?> payload,
  ) =>
      switch (node.transport) {
        TransportKind.local => local.deliver(node, context, payload),
        TransportKind.http => http.deliver(node, context, payload),
      };
}
