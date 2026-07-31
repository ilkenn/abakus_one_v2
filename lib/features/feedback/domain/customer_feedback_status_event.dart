import 'feedback_priority.dart';
import 'feedback_status.dart';

/// One immutable, append-only triage snapshot for a [CustomerFeedback]
/// ticket — the full [status]/[priority] state at that point in time, not
/// a delta. "Current status/priority" is always the latest event for a
/// given `feedbackId`. [changedByStaffId] is `null` for the automatic
/// initial event `SubmitCustomerFeedback` creates (status `open`,
/// priority `medium`) — every subsequent event is an administrator's
/// explicit triage action.
class CustomerFeedbackStatusEvent {
  const CustomerFeedbackStatusEvent({
    required this.id,
    required this.feedbackId,
    required this.status,
    required this.priority,
    this.changedByStaffId,
    required this.occurredAt,
  });

  final String id;
  final String feedbackId;
  final FeedbackStatus status;
  final FeedbackPriority priority;
  final String? changedByStaffId;
  final DateTime occurredAt;
}
