/// Allowed strike action types for audit logging.
enum StrikeAction {
  issueStrike,
  pardon,
  reset,
  suspend,
  reactivate;

  String get value {
    switch (this) {
      case StrikeAction.issueStrike:
        return 'ISSUE_STRIKE';
      case StrikeAction.pardon:
        return 'PARDON';
      case StrikeAction.reset:
        return 'RESET';
      case StrikeAction.suspend:
        return 'SUSPEND';
      case StrikeAction.reactivate:
        return 'REACTIVATE';
    }
  }

  static StrikeAction fromString(String action) {
    switch (action) {
      case 'ISSUE_STRIKE':
        return StrikeAction.issueStrike;
      case 'PARDON':
        return StrikeAction.pardon;
      case 'RESET':
        return StrikeAction.reset;
      case 'SUSPEND':
        return StrikeAction.suspend;
      case 'REACTIVATE':
        return StrikeAction.reactivate;
      default:
        throw ArgumentError.value(
          action,
          'action',
          'Unknown StrikeAction value. Must be one of: '
              'ISSUE_STRIKE, PARDON, RESET, SUSPEND, REACTIVATE',
        );
    }
  }
}

/// Represents a single audit log entry for strike management actions.
///
/// Audit logs must never be edited or deleted after creation.
class AuditLogEntry {
  final String studentId;
  final String adminId;
  final StrikeAction action;
  final int previousStrike;
  final int newStrike;
  final String reason;
  final DateTime timestamp;

  const AuditLogEntry({
    required this.studentId,
    required this.adminId,
    required this.action,
    required this.previousStrike,
    required this.newStrike,
    required this.reason,
    required this.timestamp,
  });

  factory AuditLogEntry.fromMap(Map<String, dynamic> map) {
    DateTime parseTimestamp(dynamic value) {
      if (value is DateTime) return value;
      if (value == null) {
        throw ArgumentError.notNull('timestamp');
      }
      try {
        return (value as dynamic).toDate() as DateTime;
      } catch (_) {
        throw ArgumentError.value(
          value,
          'timestamp',
          'Expected a DateTime or Firestore Timestamp.',
        );
      }
    }

    final rawStudentId = map['studentId'];
    if (rawStudentId is! String || rawStudentId.isEmpty) {
      throw ArgumentError.value(rawStudentId, 'studentId', 'Must be a non-empty string.');
    }
    final rawAdminId = map['adminId'];
    if (rawAdminId is! String || rawAdminId.isEmpty) {
      throw ArgumentError.value(rawAdminId, 'adminId', 'Must be a non-empty string.');
    }
    final rawPreviousStrike = (map['previousStrike'] as num?)?.toInt();
    if (rawPreviousStrike == null) {
      throw ArgumentError.notNull('previousStrike');
    }
    final rawNewStrike = (map['newStrike'] as num?)?.toInt();
    if (rawNewStrike == null) {
      throw ArgumentError.notNull('newStrike');
    }

    return AuditLogEntry(
      studentId: rawStudentId,
      adminId: rawAdminId,
      action: StrikeAction.fromString(map['action'] as String? ?? ''),
      previousStrike: rawPreviousStrike,
      newStrike: rawNewStrike,
      reason: map['reason'] ?? '',
      timestamp: parseTimestamp(map['timestamp']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'studentId': studentId,
      'adminId': adminId,
      'action': action.value,
      'previousStrike': previousStrike,
      'newStrike': newStrike,
      'reason': reason,
      'timestamp': timestamp,
    };
  }
}
