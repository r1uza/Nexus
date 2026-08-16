import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'model.dart';
import 'ports.dart';

final class JsonlTraceStore implements TraceSink {
  JsonlTraceStore(this.file, {this.memoryLimit = 1000});

  final File file;
  final int memoryLimit;
  final List<TraceRecord> _records = <TraceRecord>[];
  Future<void> _writeTail = Future<void>.value();

  Future<void> initialize() async {
    await file.parent.create(recursive: true);
    if (!await file.exists()) await file.create();
  }

  @override
  Future<void> append(TraceRecord record) {
    _records.add(record);
    if (_records.length > memoryLimit) _records.removeAt(0);
    final line = '${jsonEncode(record.toJson())}\n';
    final operation = _writeTail.then((_) async {
      await file.writeAsString(line, mode: FileMode.append, flush: true);
    });
    _writeTail = operation.catchError((Object _) {});
    return operation;
  }

  @override
  List<TraceRecord> recent({int limit = 100}) {
    final safeLimit = limit.clamp(1, memoryLimit);
    final start = _records.length > safeLimit ? _records.length - safeLimit : 0;
    return List<TraceRecord>.unmodifiable(_records.sublist(start).reversed);
  }
}
