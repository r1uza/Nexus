import 'dart:async';

import 'authorization.dart';
import 'config.dart';
import 'errors.dart';
import 'model.dart';
import 'ports.dart';
import 'registry.dart';

final class NexusRuntime {
  NexusRuntime({
    required this.registry,
    required this.authorization,
    required this.transport,
    required this.traceSink,
    required this.defaultTimeout,
    NexusClock clock = const SystemNexusClock(),
  }) : _clock = clock;

  final NodeRegistry registry;
  final AuthorizationManager authorization;
  final NexusTransport transport;
  final TraceSink traceSink;
  final Duration defaultTimeout;
  final NexusClock _clock;
  final Set<String> _seenCorrelations = <String>{};
  final List<String> _correlationOrder = <String>[];
  static const int _correlationLimit = 10000;

  Future<DispatchResult> dispatch(DispatchRequest request) async {
    final correlationId = request.correlationId ?? _newCorrelationId();
    final stopwatch = Stopwatch()..start();
    NodeDefinition? node;
    try {
      if (!_rememberCorrelation(correlationId)) {
        throw const NexusException(
          'duplicate_correlation',
          'The correlation ID has already been dispatched',
          statusCode: 409,
        );
      }
      node = registry.resolve(
        request.capability,
        targetNode: request.targetNode,
      );
      if (node.kind == NodeKind.operator ||
          request.capability.startsWith('execute.')) {
        authorization.consume(
          ticket: request.authorizationTicket,
          capability: request.capability,
          targetNode: node.id,
        );
      }
      final timeout = request.timeoutMs == null
          ? defaultTimeout
          : Duration(milliseconds: request.timeoutMs!);
      final response = await transport
          .deliver(
            node,
            DispatchContext(
              correlationId: correlationId,
              capability: request.capability,
              nodeId: node.id,
            ),
            request.payload,
          )
          .timeout(timeout);
      final result = DispatchResult(
        correlationId: correlationId,
        status: DispatchStatus.delivered,
        code: 'delivered',
        message: 'Dispatch delivered',
        nodeId: node.id,
        response: response,
      );
      await _trace(result, request.capability, stopwatch.elapsedMilliseconds);
      return result;
    } on TimeoutException {
      final result = DispatchResult(
        correlationId: correlationId,
        status: DispatchStatus.failed,
        code: 'timeout',
        message: 'Dispatch exceeded its timeout',
        nodeId: node?.id,
      );
      await _trace(result, request.capability, stopwatch.elapsedMilliseconds);
      return result;
    } on NexusException catch (error) {
      final result = DispatchResult(
        correlationId: correlationId,
        status: DispatchStatus.rejected,
        code: error.code,
        message: error.message,
        nodeId: node?.id,
      );
      await _trace(result, request.capability, stopwatch.elapsedMilliseconds);
      return result;
    } on Object {
      final result = DispatchResult(
        correlationId: correlationId,
        status: DispatchStatus.failed,
        code: 'downstream_failure',
        message: 'The selected node failed without a safe result',
        nodeId: node?.id,
      );
      await _trace(result, request.capability, stopwatch.elapsedMilliseconds);
      return result;
    }
  }

  Map<String, Object?> status() => <String, Object?>{
        'system': 'NEXUS.sf',
        'version': '1.0.0',
        'status': 'OPERATIONAL_LOCAL_CORE',
        'authority': 'NONE',
        'nodeCount': registry.nodes.length,
        'transport': <String>['local', 'http'],
      };

  bool _rememberCorrelation(String correlationId) {
    if (!_seenCorrelations.add(correlationId)) return false;
    _correlationOrder.add(correlationId);
    if (_correlationOrder.length > _correlationLimit) {
      _seenCorrelations.remove(_correlationOrder.removeAt(0));
    }
    return true;
  }

  String _newCorrelationId() => generateSecureIdentifier('corr');

  Future<void> _trace(
    DispatchResult result,
    String capability,
    int durationMs,
  ) =>
      traceSink.append(
        TraceRecord(
          id: generateSecureIdentifier('trace'),
          timestamp: _clock.now(),
          correlationId: result.correlationId,
          capability: capability,
          nodeId: result.nodeId,
          status: result.status,
          code: result.code,
          durationMs: durationMs,
        ),
      );
}
