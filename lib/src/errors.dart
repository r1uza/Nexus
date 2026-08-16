final class NexusException implements Exception {
  const NexusException(this.code, this.message, {this.statusCode = 400});

  final String code;
  final String message;
  final int statusCode;

  @override
  String toString() => 'NexusException($code, $message)';
}
