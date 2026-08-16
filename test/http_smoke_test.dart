import 'dart:convert';
import 'dart:io';

import 'package:nexus_sf/nexus_sf.dart';

Future<void> main() async {
  final temp = await Directory.systemTemp.createTemp('nexus-sf-http-test-');
  final token = 'http-test-token-that-is-at-least-32-characters';
  NexusHttpService? service;
  try {
    final config = NexusConfig(
      bindAddress: '127.0.0.1',
      port: 0,
      dataDirectory: temp,
      adminToken: token,
      adminTokenWasGenerated: false,
      allowedEndpointHosts: <String>{},
    );
    final components = await NexusBootstrap.create(config);
    service = NexusHttpService(runtime: components.runtime, config: config);
    final port = await service.start();
    final base = Uri.parse('http://127.0.0.1:$port');

    final health = await _request(base.resolve('/healthz'));
    _expect(health.status == HttpStatus.ok, 'public health returns 200');

    final denied = await _request(base.resolve('/v1/nodes'));
    _expect(
      denied.status == HttpStatus.unauthorized,
      'control plane requires auth',
    );

    final echo = await _request(
      base.resolve('/v1/dispatch'),
      method: 'POST',
      token: token,
      body: <String, Object?>{
        'capability': 'system.echo',
        'correlationId': 'http.echo-1',
        'payload': <String, Object?>{'secret': 'super-secret-value'},
      },
    );
    _expect(
      echo.status == HttpStatus.ok,
      'authenticated dispatch is delivered',
    );

    final issued = await _request(
      base.resolve('/v1/authorizations'),
      method: 'POST',
      token: token,
      body: <String, Object?>{
        'subject': 'person.http-test',
        'capability': 'execute.echo',
        'targetNode': 'eco.local',
        'ttlSeconds': 30,
      },
    );
    _expect(issued.status == HttpStatus.created, 'authorization can be issued');
    final ticket = issued.json['ticket'];
    _expect(ticket is String, 'authorization response contains a ticket');

    final execution = await _request(
      base.resolve('/v1/dispatch'),
      method: 'POST',
      token: token,
      body: <String, Object?>{
        'capability': 'execute.echo',
        'targetNode': 'eco.local',
        'correlationId': 'http.execute-1',
        'authorizationTicket': ticket,
        'payload': <String, Object?>{'operation': 'echo'},
      },
    );
    _expect(
      execution.status == HttpStatus.ok,
      'authorized execution is delivered',
    );

    final endpointDenied = await _request(
      base.resolve('/v1/nodes'),
      method: 'POST',
      token: token,
      body: <String, Object?>{
        'id': 'remote.denied',
        'kind': 'service',
        'capabilities': <String>['remote.call'],
        'transport': 'http',
        'endpoint': 'https://example.com/hook',
      },
    );
    _expect(
      endpointDenied.status == HttpStatus.forbidden,
      'SSRF allowlist is enforced',
    );

    final traces = await _request(
      base.resolve('/v1/traces?limit=10'),
      token: token,
    );
    _expect(traces.status == HttpStatus.ok, 'traces are readable');
    _expect(
      !traces.raw.contains('super-secret-value'),
      'traces do not contain payloads',
    );
    stdout.writeln('HTTP SMOKE: PASS');
  } finally {
    await service?.close();
    await temp.delete(recursive: true);
  }
}

Future<_HttpResult> _request(
  Uri uri, {
  String method = 'GET',
  String? token,
  Map<String, Object?>? body,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, uri);
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final raw = await utf8.decoder.bind(response).join();
    final Object? decoded = raw.isEmpty ? <String, Object?>{} : jsonDecode(raw);
    final json = <String, Object?>{};
    if (decoded is Map<Object?, Object?>) {
      for (final entry in decoded.entries) {
        if (entry.key is String) json[entry.key! as String] = entry.value;
      }
    }
    return _HttpResult(response.statusCode, raw, json);
  } finally {
    client.close(force: true);
  }
}

final class _HttpResult {
  const _HttpResult(this.status, this.raw, this.json);

  final int status;
  final String raw;
  final Map<String, Object?> json;
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('FAILED: $message');
}
