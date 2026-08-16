import 'dart:io';

import 'package:nexus_sf/nexus_sf.dart';

Future<void> main() async {
  var publicBindRejected = false;
  try {
    NexusConfig.fromEnvironmentAndArgs(
      <String, String>{'NEXUS_BIND': '0.0.0.0'},
      <String>[],
    );
  } on Object {
    publicBindRejected = true;
  }
  _expect(
    publicBindRejected,
    'non-loopback bind without an explicit token is rejected',
  );

  final temp = await Directory.systemTemp.createTemp('nexus-sf-core-test-');
  try {
    final config = NexusConfig(
      bindAddress: '127.0.0.1',
      port: 0,
      dataDirectory: temp,
      adminToken: 'test-token-that-is-at-least-32-characters',
      adminTokenWasGenerated: false,
      allowedEndpointHosts: <String>{},
    );
    final components = await NexusBootstrap.create(config);
    final runtime = components.runtime;

    final echo = await runtime.dispatch(
      DispatchRequest(
        capability: 'system.echo',
        correlationId: 'core.echo-1',
        payload: <String, Object?>{'message': 'hello'},
      ),
    );
    _expect(echo.status == DispatchStatus.delivered, 'local echo is delivered');

    final generated = await runtime.dispatch(
      DispatchRequest(
        capability: 'system.echo',
        payload: <String, Object?>{'message': 'generated correlation'},
      ),
    );
    final generatedReplay = await runtime.dispatch(
      DispatchRequest(
        capability: 'system.echo',
        correlationId: generated.correlationId,
        payload: <String, Object?>{},
      ),
    );
    _expect(
      generatedReplay.code == 'duplicate_correlation',
      'generated correlation IDs are valid reusable protocol identifiers',
    );

    final unauthorized = await runtime.dispatch(
      DispatchRequest(
        capability: 'execute.echo',
        correlationId: 'core.execute-1',
        payload: <String, Object?>{'operation': 'echo'},
      ),
    );
    _expect(
      unauthorized.code == 'authorization_required',
      'operator fails closed without a ticket',
    );

    final authorization = runtime.authorization.issue(
      subject: 'person.test',
      capability: 'execute.echo',
      targetNode: 'eco.local',
    );
    final authorized = await runtime.dispatch(
      DispatchRequest(
        capability: 'execute.echo',
        targetNode: 'eco.local',
        correlationId: 'core.execute-2',
        authorizationTicket: authorization.ticket,
        payload: <String, Object?>{'operation': 'echo'},
      ),
    );
    _expect(
      authorized.status == DispatchStatus.delivered,
      'matching one-use ticket permits execution',
    );

    final replay = await runtime.dispatch(
      DispatchRequest(
        capability: 'execute.echo',
        targetNode: 'eco.local',
        correlationId: 'core.execute-3',
        authorizationTicket: authorization.ticket,
        payload: <String, Object?>{'operation': 'echo'},
      ),
    );
    _expect(
      replay.code == 'authorization_invalid',
      'ticket replay is rejected',
    );

    final duplicate = await runtime.dispatch(
      DispatchRequest(
        capability: 'system.echo',
        correlationId: 'core.echo-1',
        payload: <String, Object?>{'message': 'duplicate'},
      ),
    );
    _expect(
      duplicate.code == 'duplicate_correlation',
      'duplicate correlation is rejected',
    );

    runtime.registry
      ..register(
        NodeDefinition(
          id: 'external.one',
          kind: NodeKind.service,
          capabilities: <String>{'service.ambiguous'},
          transport: TransportKind.http,
          endpoint: Uri.parse('http://127.0.0.1:9001/hook'),
        ),
      )
      ..register(
        NodeDefinition(
          id: 'external.two',
          kind: NodeKind.service,
          capabilities: <String>{'service.ambiguous'},
          transport: TransportKind.http,
          endpoint: Uri.parse('http://localhost:9002/hook'),
        ),
      );
    final ambiguous = await runtime.dispatch(
      DispatchRequest(
        capability: 'service.ambiguous',
        correlationId: 'core.ambiguous-1',
        payload: <String, Object?>{},
      ),
    );
    _expect(
      ambiguous.code == 'route_ambiguous',
      'ambiguous route fails closed',
    );

    var immutableRejected = false;
    try {
      runtime.registry.remove('eco.local');
    } on Object {
      immutableRejected = true;
    }
    _expect(immutableRejected, 'built-in nodes are immutable');

    for (final trace in components.traceStore.recent()) {
      final keys = trace.toJson().keys.toSet();
      _expect(!keys.contains('payload'), 'trace excludes request payload');
      _expect(!keys.contains('response'), 'trace excludes response payload');
      _expect(!keys.contains('authorizationTicket'), 'trace excludes tickets');
    }
    stdout.writeln('CORE CONTRACTS: PASS');
  } finally {
    await temp.delete(recursive: true);
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('FAILED: $message');
}
