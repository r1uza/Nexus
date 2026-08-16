import 'dart:io';

Future<void> main() async {
  final gates = <List<String>>[
    <String>['run', 'test/core_contract_test.dart'],
    <String>['run', 'test/http_smoke_test.dart'],
    <String>['run', 'bin/nexus_sf.dart', 'demo'],
  ];
  for (final gate in gates) {
    stdout.writeln('dart ${gate.join(' ')}');
    final result = await Process.run(
      Platform.resolvedExecutable,
      gate,
      workingDirectory: Directory.current.path,
    );
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    if (result.exitCode != 0) {
      exitCode = result.exitCode;
      return;
    }
  }
  stdout.writeln('NEXUS.sf VERIFICATION: PASS');
}
