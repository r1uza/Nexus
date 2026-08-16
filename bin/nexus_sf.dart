import 'dart:io';

import 'package:nexus_sf/src/cli.dart';

Future<void> main(List<String> args) async {
  exitCode = await runNexusCli(args);
}
