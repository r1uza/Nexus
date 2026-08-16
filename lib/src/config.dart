import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'errors.dart';

final class NexusConfig {
  NexusConfig({
    required this.bindAddress,
    required this.port,
    required this.dataDirectory,
    required this.adminToken,
    required this.adminTokenWasGenerated,
    required this.allowedEndpointHosts,
    this.maxBodyBytes = 1024 * 1024,
    this.requestTimeout = const Duration(seconds: 5),
  }) {
    if (port < 0 || port > 65535) {
      throw const NexusException('invalid_port', 'Port must be 0..65535');
    }
    if (maxBodyBytes < 1024 || maxBodyBytes > 16 * 1024 * 1024) {
      throw const NexusException(
        'invalid_body_limit',
        'Body limit must be between 1 KiB and 16 MiB',
      );
    }
    if (requestTimeout.inMilliseconds < 50 ||
        requestTimeout.inMilliseconds > 30000) {
      throw const NexusException(
        'invalid_request_timeout',
        'Request timeout must be between 50 and 30000 ms',
      );
    }
    if (adminToken.length < 32) {
      throw const NexusException(
        'weak_admin_token',
        'Admin token must contain at least 32 characters',
      );
    }
    if (!isLoopbackHost(bindAddress) && adminTokenWasGenerated) {
      throw const NexusException(
        'explicit_token_required',
        'A non-loopback bind requires an explicit NEXUS_ADMIN_TOKEN',
      );
    }
  }

  factory NexusConfig.fromEnvironmentAndArgs(
    Map<String, String> environment,
    List<String> args,
  ) {
    final options = _parseOptions(args);
    final bindAddress = options['bind'] ??
        environment['NEXUS_BIND'] ??
        InternetAddress.loopbackIPv4.address;
    final port = _parseInt(
      options['port'] ?? environment['NEXUS_PORT'] ?? '8787',
      'port',
    );
    final dataDirectory = Directory(
      options['data-dir'] ?? environment['NEXUS_DATA_DIR'] ?? '.nexus-sf',
    );
    final explicitToken = options['token'] ?? environment['NEXUS_ADMIN_TOKEN'];
    final generated = explicitToken == null || explicitToken.isEmpty;
    final token = generated ? generateSecureToken() : explicitToken;
    final maxBody = _parseInt(
      environment['NEXUS_MAX_BODY_BYTES'] ?? '1048576',
      'NEXUS_MAX_BODY_BYTES',
    );
    final timeoutMs = _parseInt(
      environment['NEXUS_REQUEST_TIMEOUT_MS'] ?? '5000',
      'NEXUS_REQUEST_TIMEOUT_MS',
    );
    final hostSource = <String>{
      ...?environment['NEXUS_ALLOWED_ENDPOINT_HOSTS']
          ?.split(',')
          .map((String value) => value.trim().toLowerCase())
          .where((String value) => value.isNotEmpty),
      ...?options['allow-host']
          ?.split(',')
          .map((String value) => value.trim().toLowerCase())
          .where((String value) => value.isNotEmpty),
    };
    return NexusConfig(
      bindAddress: bindAddress,
      port: port,
      dataDirectory: dataDirectory,
      adminToken: token,
      adminTokenWasGenerated: generated,
      allowedEndpointHosts: hostSource,
      maxBodyBytes: maxBody,
      requestTimeout: Duration(milliseconds: timeoutMs),
    );
  }

  final String bindAddress;
  final int port;
  final Directory dataDirectory;
  final String adminToken;
  final bool adminTokenWasGenerated;
  final Set<String> allowedEndpointHosts;
  final int maxBodyBytes;
  final Duration requestTimeout;

  Map<String, Object?> publicJson({int? actualPort}) => <String, Object?>{
        'bind': bindAddress,
        'port': actualPort ?? port,
        'dataDirectory': dataDirectory.path,
        'maxBodyBytes': maxBodyBytes,
        'requestTimeoutMs': requestTimeout.inMilliseconds,
        'allowedEndpointHosts': allowedEndpointHosts.toList()..sort(),
        'adminTokenGenerated': adminTokenWasGenerated,
      };
}

bool isLoopbackHost(String host) {
  final normalized = host.toLowerCase();
  if (normalized == 'localhost' || normalized == '::1') return true;
  final address = InternetAddress.tryParse(normalized);
  return address?.isLoopback ?? false;
}

String generateSecureToken({int byteLength = 32}) {
  final random = Random.secure();
  final bytes = List<int>.generate(byteLength, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

String generateSecureIdentifier(String prefix, {int byteLength = 18}) {
  final random = Random.secure();
  final buffer = StringBuffer('$prefix.');
  for (var index = 0; index < byteLength; index += 1) {
    buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

int _parseInt(String source, String field) {
  final value = int.tryParse(source);
  if (value == null) {
    throw NexusException('invalid_integer', '$field must be an integer');
  }
  return value;
}

Map<String, String> _parseOptions(List<String> args) {
  final result = <String, String>{};
  for (var index = 0; index < args.length; index += 1) {
    final argument = args[index];
    if (!argument.startsWith('--')) {
      throw NexusException('unknown_argument', 'Unknown argument: $argument');
    }
    final equals = argument.indexOf('=');
    if (equals > 2) {
      result[argument.substring(2, equals)] = argument.substring(equals + 1);
      continue;
    }
    final key = argument.substring(2);
    if (index + 1 >= args.length || args[index + 1].startsWith('--')) {
      throw NexusException('missing_argument', '--$key requires a value');
    }
    result[key] = args[index + 1];
    index += 1;
  }
  const allowed = <String>{'bind', 'port', 'data-dir', 'token', 'allow-host'};
  for (final key in result.keys) {
    if (!allowed.contains(key)) {
      throw NexusException('unknown_option', 'Unknown option: --$key');
    }
  }
  return result;
}
