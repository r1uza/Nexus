import 'config.dart';
import 'errors.dart';
import 'model.dart';
import 'ports.dart';

final class AuthorizationManager {
  AuthorizationManager({NexusClock clock = const SystemNexusClock()})
      : _clock = clock;

  final NexusClock _clock;
  final Map<String, _AuthorizationRecord> _records =
      <String, _AuthorizationRecord>{};

  IssuedAuthorization issue({
    required String subject,
    required String capability,
    String? targetNode,
    Duration ttl = const Duration(seconds: 60),
  }) {
    validateIdentifier(subject, 'subject');
    validateIdentifier(capability, 'capability');
    if (!capability.startsWith('execute.')) {
      throw const NexusException(
        'invalid_authorization_capability',
        'Authorization tickets are only issued for execute.* capabilities',
      );
    }
    if (targetNode != null) validateIdentifier(targetNode, 'targetNode');
    if (ttl.inSeconds < 1 || ttl.inSeconds > 300) {
      throw const NexusException(
        'invalid_authorization_ttl',
        'Authorization TTL must be between 1 and 300 seconds',
      );
    }
    _purgeExpired();
    final ticket = generateSecureToken();
    final expiresAt = _clock.now().add(ttl);
    final issued = IssuedAuthorization(
      ticket: ticket,
      subject: subject,
      capability: capability,
      targetNode: targetNode,
      expiresAt: expiresAt,
    );
    _records[ticket] = _AuthorizationRecord(issued);
    return issued;
  }

  void consume({
    required String? ticket,
    required String capability,
    required String targetNode,
  }) {
    if (ticket == null) {
      throw const NexusException(
        'authorization_required',
        'An execution authorization ticket is required',
        statusCode: 403,
      );
    }
    final record = _records.remove(ticket);
    if (record == null ||
        !_clock.now().isBefore(record.authorization.expiresAt)) {
      throw const NexusException(
        'authorization_invalid',
        'Authorization ticket is unknown, expired, or already used',
        statusCode: 403,
      );
    }
    final authorization = record.authorization;
    if (authorization.capability != capability ||
        (authorization.targetNode != null &&
            authorization.targetNode != targetNode)) {
      throw const NexusException(
        'authorization_invalid',
        'Authorization ticket does not match the dispatch',
        statusCode: 403,
      );
    }
  }

  void _purgeExpired() {
    final now = _clock.now();
    _records.removeWhere(
      (String _, _AuthorizationRecord record) =>
          !now.isBefore(record.authorization.expiresAt),
    );
  }
}

final class _AuthorizationRecord {
  const _AuthorizationRecord(this.authorization);

  final IssuedAuthorization authorization;
}
