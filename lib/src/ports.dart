import 'model.dart';

typedef LocalNodeHandler = Future<Map<String, Object?>> Function(
  DispatchContext context,
  Map<String, Object?> payload,
);

final class DispatchContext {
  const DispatchContext({
    required this.correlationId,
    required this.capability,
    required this.nodeId,
  });

  final String correlationId;
  final String capability;
  final String nodeId;
}

abstract interface class NexusTransport {
  Future<Map<String, Object?>> deliver(
    NodeDefinition node,
    DispatchContext context,
    Map<String, Object?> payload,
  );
}

abstract interface class TraceSink {
  Future<void> append(TraceRecord record);

  List<TraceRecord> recent({int limit = 100});
}

abstract interface class NexusClock {
  DateTime now();
}

final class SystemNexusClock implements NexusClock {
  const SystemNexusClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}
