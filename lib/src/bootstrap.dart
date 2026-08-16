import 'dart:io';

import 'authorization.dart';
import 'config.dart';
import 'model.dart';
import 'ports.dart';
import 'registry.dart';
import 'runtime.dart';
import 'store.dart';
import 'transports.dart';

final class NexusComponents {
  const NexusComponents({
    required this.runtime,
    required this.traceStore,
    required this.localTransport,
  });

  final NexusRuntime runtime;
  final JsonlTraceStore traceStore;
  final LocalTransport localTransport;
}

abstract final class NexusBootstrap {
  static Future<NexusComponents> create(
    NexusConfig config, {
    NexusClock clock = const SystemNexusClock(),
  }) async {
    final endpointPolicy = EndpointPolicy(config.allowedEndpointHosts);
    final registry = NodeRegistry(endpointPolicy: endpointPolicy);
    final local = LocalTransport();
    _registerBuiltins(registry, local);
    final traceStore = JsonlTraceStore(
      File('${config.dataDirectory.path}${Platform.pathSeparator}traces.jsonl'),
    );
    await traceStore.initialize();
    final transport = TransportRouter(
      local: local,
      http: HttpNodeTransport(
        endpointPolicy: endpointPolicy,
        maxResponseBytes: config.maxBodyBytes,
      ),
    );
    return NexusComponents(
      runtime: NexusRuntime(
        registry: registry,
        authorization: AuthorizationManager(clock: clock),
        transport: transport,
        traceSink: traceStore,
        defaultTimeout: config.requestTimeout,
        clock: clock,
      ),
      traceStore: traceStore,
      localTransport: local,
    );
  }

  static void _registerBuiltins(NodeRegistry registry, LocalTransport local) {
    final definitions = <NodeDefinition>[
      NodeDefinition(
        id: 'nexus.local',
        kind: NodeKind.service,
        capabilities: <String>{'system.echo'},
        transport: TransportKind.local,
        mutable: false,
      ),
      NodeDefinition(
        id: 'uvo.local',
        kind: NodeKind.interface,
        capabilities: <String>{'interface.echo'},
        transport: TransportKind.local,
        mutable: false,
      ),
      NodeDefinition(
        id: 'ugai.local',
        kind: NodeKind.intelligence,
        capabilities: <String>{'intelligence.echo'},
        transport: TransportKind.local,
        mutable: false,
      ),
      NodeDefinition(
        id: 'eve.local',
        kind: NodeKind.verifier,
        capabilities: <String>{'verify.payload'},
        transport: TransportKind.local,
        mutable: false,
      ),
      NodeDefinition(
        id: 'eco.local',
        kind: NodeKind.operator,
        capabilities: <String>{'execute.echo'},
        transport: TransportKind.local,
        mutable: false,
      ),
    ];
    for (final definition in definitions) {
      registry.register(definition);
    }
    local
      ..register(
        'nexus.local',
        (DispatchContext context, Map<String, Object?> payload) async =>
            <String, Object?>{'echo': payload, 'handledBy': context.nodeId},
      )
      ..register(
        'uvo.local',
        (DispatchContext context, Map<String, Object?> payload) async =>
            <String, Object?>{'echo': payload, 'surface': 'UVO'},
      )
      ..register(
        'ugai.local',
        (DispatchContext context, Map<String, Object?> payload) async =>
            <String, Object?>{
          'echo': payload,
          'agent': 'UGAI',
          'reasoningClaimed': false,
        },
      )
      ..register(
        'eve.local',
        (DispatchContext context, Map<String, Object?> payload) async =>
            <String, Object?>{
          'verified': true,
          'classification': 'STRUCTURALLY_VALID',
          'fieldCount': payload.length,
        },
      )
      ..register(
        'eco.local',
        (DispatchContext context, Map<String, Object?> payload) async =>
            <String, Object?>{
          'executed': true,
          'operation': 'echo',
          'echo': payload,
        },
      );
  }
}
