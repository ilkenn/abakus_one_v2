import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/customer_feedback_repository.dart';
import '../../data/customer_feedback_status_event_repository.dart';
import '../../domain/customer_feedback_status_event.dart';
import '../../domain/feedback_priority.dart';
import '../../domain/feedback_status.dart';
import '../identity/customer_feedback_status_event_id_generator.dart';

/// An administrator re-triages a [CustomerFeedback] ticket — manager-only
/// ([PosAuthorizedAction.manageCustomerFeedback]). Appends a new
/// [CustomerFeedbackStatusEvent] rather than mutating anything — the full
/// triage history is always preserved. [priority] is optional: when
/// omitted, the ticket's current priority carries forward unchanged.
class UpdateCustomerFeedbackStatus {
  const UpdateCustomerFeedbackStatus({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required CustomerFeedbackStatusEventIdGenerator idGenerator,
    required CustomerFeedbackRepository feedbackRepository,
    required CustomerFeedbackStatusEventRepository statusEventRepository,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _feedbackRepository = feedbackRepository,
        _statusEventRepository = statusEventRepository;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final CustomerFeedbackStatusEventIdGenerator _idGenerator;
  final CustomerFeedbackRepository _feedbackRepository;
  final CustomerFeedbackStatusEventRepository _statusEventRepository;

  Future<CustomerFeedbackStatusEvent> call({
    required String feedbackId,
    required FeedbackStatus status,
    FeedbackPriority? priority,
    required String performedByStaffId,
  }) async {
    const action = PosAuthorizedAction.manageCustomerFeedback;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final feedback = await _feedbackRepository.findById(feedbackId);
    if (feedback == null) {
      throw UnknownCrmEntityViolation(
        entityName: 'CustomerFeedback',
        id: feedbackId,
      );
    }

    final history = await _statusEventRepository.findByFeedbackId(feedbackId);
    final currentPriority =
        history.isEmpty ? FeedbackPriority.medium : history.last.priority;

    final event = CustomerFeedbackStatusEvent(
      id: _idGenerator.nextEventId(),
      feedbackId: feedbackId,
      status: status,
      priority: priority ?? currentPriority,
      changedByStaffId: performedByStaffId,
      occurredAt: _clock.now(),
    );
    await _statusEventRepository.append(event);
    return event;
  }
}
