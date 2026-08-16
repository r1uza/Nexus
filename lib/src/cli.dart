import 'dart:convert';
import 'dart:io';

import 'bootstrap.dart';
import 'config.dart';
import 'errors.dart';
import 'model.dart';
import 'server.dart';

Future<int> runNexusCli(
  List<String> args, {
  Map<String, String>? environment,
}) async {
  final command = args.isEmpty ? 'help' : args.first;
  final options = args.isEmpty ? <String>[] : args.sublist(1);
  try {
    return switch (command) {
      'serve' => await _serve(options, environment ?? Platform.environment),
      'doctor' => await _doctor(options, environment ?? Platform.environment),
      'demo' => await _demo(options, environment ?? Platform.environment),
      'healthcheck' => await _healthcheck(
          options,
          environment ?? Platform.environment,
        ),
      'help' || '--help' || '-h' => _help(),
      _ => throw NexusException('unknown_command', 'Unknown command: $command'),
    };
  } on NexusException catch (error) {
    stderr.writeln('${error.code}: ${error.message}');
    return 2;
  } on Object catch (error) {
    stderr.writeln('fatal: $error');
    return 1;
  }
}

Future<int> _serve(List<String> args, Map<String, String> environment) async {
  final config = NexusConfig.fromEnvironmentAndArgs(environment, args);
  final components = await NexusBootstrap.create(config);
  final service = NexusHttpService(runtime: components.runtime, config: config);
  final actualPort = await service.start();
  stdout.writeln(
    jsonEncode(<String, Object?>{
      'event': 'started',
      ...config.publicJson(actualPort: actualPort),
    }),
  );
  if (config.adminTokenWasGenerated) {
    stdout.writeln('NEXUS_ADMIN_TOKEN=${config.adminToken}');
  }
  if (Platform.isWindows) {
    await ProcessSignal.sigint.watch().first;
  } else {
    await Future.any<Object?>(<Future<Object?>>[
      ProcessSignal.sigint.watch().first,
      ProcessSignal.sigterm.watch().first,
    ]);
  }
  await service.close();
  stdout.writeln(jsonEncode(<String, Object?>{'event': 'stopped'}));
  return 0;
}

Future<int> _doctor(List<String> args, Map<String, String> environment) async {
  final config = NexusConfig.fromEnvironmentAndArgs(environment, args);
  final parent = config.dataDirectory.absolute.parent;
  final report = <String, Object?>{
    'system': 'NEXUS.sf',
    'version': '1.0.0',
    'dart': Platform.version,
    'configuration': config.publicJson(),
    'checks': <String, Object?>{
      'loopbackOrExplicitToken':
          isLoopbackHost(config.bindAddress) || !config.adminTokenWasGenerated,
      'dataParentExists': await parent.exists(),
      'endpointAllowlistCount': config.allowedEndpointHosts.length,
    },
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
  return 0;
}

Future<int> _demo(List<String> args, Map<String, String> environment) async {
  final temp = await Directory.systemTemp.createTemp('nexus-sf-demo-');
  try {
    final demoEnvironment = <String, String>{
      ...environment,
      'NEXUS_DATA_DIR': temp.path,
      'NEXUS_ADMIN_TOKEN': 'demo-token-that-is-at-least-32-characters',
    };
    final config = NexusConfig.fromEnvironmentAndArgs(demoEnvironment, args);
    final components = await NexusBootstrap.create(config);
    final echo = await components.runtime.dispatch(
      DispatchRequest(
        capability: 'system.echo',
        payload: <String, Object?>{'message': 'NEXUS.sf operational'},
      ),
    );
    final verification = await components.runtime.dispatch(
      DispatchRequest(
        capability: 'verify.payload',
        payload: <String, Object?>{'claim': 'demo'},
      ),
    );
    final authorization = components.runtime.authorization.issue(
      subject: 'person.demo',
      capability: 'execute.echo',
      targetNode: 'eco.local',
    );
    final execution = await components.runtime.dispatch(
      DispatchRequest(
        capability: 'execute.echo',
        targetNode: 'eco.local',
        authorizationTicket: authorization.ticket,
        payload: <String, Object?>{'operation': 'harmless-echo'},
      ),
    );
    final output = <String, Object?>{
      'echo': echo.toJson(),
      'verification': verification.toJson(),
      'execution': execution.toJson(),
      'traceCount': components.traceStore.recent().length,
    };
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(output));
    return echo.status == DispatchStatus.delivered &&
            verification.status == DispatchStatus.delivered &&
            execution.status == DispatchStatus.delivered
        ? 0
        : 1;
  } finally {
    await temp.delete(recursive: true);
  }
}

Future<int> _healthcheck(
  List<String> args,
  Map<String, String> environment,
) async {
  final config = NexusConfig.fromEnvironmentAndArgs(environment, args);
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse('http://${config.bindAddress}:${config.port}/healthz'),
    );
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode == HttpStatus.ok ? 0 : 1;
  } finally {
    client.close(force: true);
  }
}

int _help() {
  stdout.writeln(
    '''
NEXUS.sf 1.0.0

Usage:
  nexus-sf serve [--bind HOST] [--port PORT] [--data-dir PATH]
  nexus-sf doctor
  nexus-sf demo
  nexus-sf healthcheck

Configuration is also accepted through the NEXUS_* variables documented in
.env.example. Control-plane requests use Authorization: Bearer <token>.
'''
        .trim(),
  );
  return 0;
}
