import 'errors.dart';
import 'json_support.dart';

final RegExp _identifierPattern = RegExp(
  r'^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$',
);

void validateIdentifier(String value, String field) {
  if (value.length > 128 || !_identifierPattern.hasMatch(value)) {
    throw NexusException(
      'invalid_identifier',
      '$field must match ${_identifierPattern.pattern}',
    );
  }
}

enum NodeKind {
  interface,
  intelligence,
  verifier,
  operator,
  service;

  static NodeKind parse(String value) {
    for (final candidate in NodeKind.values) {
      if (candidate.name == value) return candidate;
    }
    throw NexusException('invalid_node_kind', 'Unsupported node kind: $value');
  }
}

enum TransportKind {
  local,
  http;

  static TransportKind parse(String value) {
    for (final candidate in TransportKind.values) {
      if (candidate.name == value) return candidate;
    }
    throw NexusException('invalid_transport', 'Unsupported transport: $value');
  }
}

final class NodeDefinition {
  NodeDefinition({
    required this.id,
    required this.kind,
    required Set<String> capabilities,
    required this.transport,
    this.endpoint,
    this.enabled = true,
    this.mutable = true,
  }) : capabilities = Set<String>.unmodifiable(capabilities) {
    validateIdentifier(id, 'id');
    if (capabilities.isEmpty || capabilities.length > 64) {
      throw const NexusException(
        'invalid_capabilities',
        'A node needs between 1 and 64 capabilities',
      );
    }
    for (final capability in capabilities) {
      validateIdentifier(capability, 'capability');
    }
    if (transport == TransportKind.http && endpoint == null) {
      throw const NexusException(
        'endpoint_required',
        'HTTP nodes require an endpoint',
      );
    }
    if (transport == TransportKind.local && endpoint != null) {
      throw const NexusException(
        'endpoint_forbidden',
        'Local nodes cannot declare an endpoint',
      );
    }
  }

  factory NodeDefinition.fromJson(Map<String, Object?> json) {
    final id = requireString(json, 'id', maxLength: 128);
    final kind = NodeKind.parse(requireString(json, 'kind', maxLength: 32));
    final transport = TransportKind.parse(
      optionalString(json, 'transport', maxLength: 16) ?? 'http',
    );
    final endpointText = optionalString(json, 'endpoint');
    return NodeDefinition(
      id: id,
      kind: kind,
      capabilities: requireStringList(json, 'capabilities').toSet(),
      transport: transport,
      endpoint: endpointText == null ? null : Uri.parse(endpointText),
      enabled: optionalBool(json, 'enabled', fallback: true),
    );
  }

  final String id;
  final NodeKind kind;
  final Set<String> capabilities;
  final TransportKind transport;
  final Uri? endpoint;
  final bool enabled;
  final bool mutable;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'kind': kind.name,
        'capabilities': capabilities.toList()..sort(),
        'transport': transport.name,
        if (endpoint != null) 'endpoint': endpoint.toString(),
        'enabled': enabled,
        'mutable': mutable,
      };
}

final class DispatchRequest {
  DispatchRequest({
    required this.capability,
    required Map<String, Object?> payload,
    this.correlationId,
    this.targetNode,
    this.authorizationTicket,
    this.timeoutMs,
  }) : payload = Map<String, Object?>.unmodifiable(payload) {
    validateIdentifier(capability, 'capability');
    if (correlationId != null)
      validateIdentifier(correlationId!, 'correlationId');
    if (targetNode != null) validateIdentifier(targetNode!, 'targetNode');
    if (timeoutMs != null && (timeoutMs! < 50 || timeoutMs! > 30000)) {
      throw const NexusException(
        'invalid_timeout',
        'timeoutMs must be between 50 and 30000',
      );
    }
  }

  factory DispatchRequest.fromJson(Map<String, Object?> json) =>
      DispatchRequest(
        capability: requireString(json, 'capability', maxLength: 128),
        payload: json['payload'] == null
            ? <String, Object?>{}
            : requireObject(json['payload'], 'payload'),
        correlationId: optionalString(json, 'correlationId', maxLength: 128),
        targetNode: optionalString(json, 'targetNode', maxLength: 128),
        authorizationTicket: optionalString(
          json,
          'authorizationTicket',
          maxLength: 512,
        ),
        timeoutMs: optionalInt(json, 'timeoutMs'),
      );

  final String capability;
  final Map<String, Object?> payload;
  final String? correlationId;
  final String? targetNode;
  final String? authorizationTicket;
  final int? timeoutMs;
}

enum DispatchStatus { delivered, rejected, failed }

final class DispatchResult {
  const DispatchResult({
    required this.correlationId,
    required this.status,
    required this.code,
    required this.message,
    this.nodeId,
    this.response,
  });

  final String correlationId;
  final DispatchStatus status;
  final String code;
  final String message;
  final String? nodeId;
  final Map<String, Object?>? response;

  int get httpStatus => switch (code) {
        'authorization_required' || 'authorization_invalid' => 403,
        'duplicate_correlation' || 'route_ambiguous' => 409,
        'route_not_found' => 404,
        'timeout' => 504,
        _ => status == DispatchStatus.delivered ? 200 : 502,
      };

  Map<String, Object?> toJson() => <String, Object?>{
        'correlationId': correlationId,
        'status': status.name,
        'code': code,
        'message': message,
        if (nodeId != null) 'nodeId': nodeId,
        if (response != null) 'response': response,
      };
}

final class TraceRecord {
  const TraceRecord({
    required this.id,
    required this.timestamp,
    required this.correlationId,
    required this.capability,
    required this.status,
    required this.code,
    required this.durationMs,
    this.nodeId,
  });

  final String id;
  final DateTime timestamp;
  final String correlationId;
  final String capability;
  final DispatchStatus status;
  final String code;
  final int durationMs;
  final String? nodeId;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'correlationId': correlationId,
        'capability': capability,
        'status': status.name,
        'code': code,
        'durationMs': durationMs,
        if (nodeId != null) 'nodeId': nodeId,
      };
}

final class IssuedAuthorization {
  const IssuedAuthorization({
    required this.ticket,
    required this.subject,
    required this.capability,
    required this.expiresAt,
    this.targetNode,
  });

  final String ticket;
  final String subject;
  final String capability;
  final DateTime expiresAt;
  final String? targetNode;

  Map<String, Object?> toJson() => <String, Object?>{
        'ticket': ticket,
        'subject': subject,
        'capability': capability,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        if (targetNode != null) 'targetNode': targetNode,
      };
}
