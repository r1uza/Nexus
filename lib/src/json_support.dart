import 'errors.dart';

Map<String, Object?> requireObject(Object? value, String field) {
  if (value is! Map<Object?, Object?>) {
    throw NexusException('invalid_json', '$field must be a JSON object');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw NexusException('invalid_json', '$field contains a non-string key');
    }
    result[entry.key! as String] = entry.value;
  }
  return result;
}

String requireString(
  Map<String, Object?> value,
  String field, {
  int maxLength = 256,
}) {
  final candidate = value[field];
  if (candidate is! String ||
      candidate.isEmpty ||
      candidate.length > maxLength) {
    throw NexusException(
      'invalid_field',
      '$field must be a non-empty string up to $maxLength characters',
    );
  }
  return candidate;
}

String? optionalString(
  Map<String, Object?> value,
  String field, {
  int maxLength = 2048,
}) {
  final candidate = value[field];
  if (candidate == null) return null;
  if (candidate is! String ||
      candidate.isEmpty ||
      candidate.length > maxLength) {
    throw NexusException(
      'invalid_field',
      '$field must be a non-empty string up to $maxLength characters',
    );
  }
  return candidate;
}

int? optionalInt(Map<String, Object?> value, String field) {
  final candidate = value[field];
  if (candidate == null) return null;
  if (candidate is! int) {
    throw NexusException('invalid_field', '$field must be an integer');
  }
  return candidate;
}

bool optionalBool(
  Map<String, Object?> value,
  String field, {
  bool fallback = false,
}) {
  final candidate = value[field];
  if (candidate == null) return fallback;
  if (candidate is! bool) {
    throw NexusException('invalid_field', '$field must be a boolean');
  }
  return candidate;
}

List<String> requireStringList(
  Map<String, Object?> value,
  String field, {
  int maxItems = 64,
}) {
  final candidate = value[field];
  if (candidate is! List<Object?> ||
      candidate.isEmpty ||
      candidate.length > maxItems) {
    throw NexusException(
      'invalid_field',
      '$field must be a non-empty list with at most $maxItems items',
    );
  }
  final result = <String>[];
  for (final item in candidate) {
    if (item is! String || item.isEmpty || item.length > 128) {
      throw NexusException('invalid_field', '$field contains an invalid value');
    }
    result.add(item);
  }
  return result;
}
