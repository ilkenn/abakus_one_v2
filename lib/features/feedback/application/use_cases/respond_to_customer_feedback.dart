import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/customer_feedback_repository.dart';
import '../../data/customer_feedback_response_repository.dart';
import '../../domain/customer_feedback_response.dart';
import '../identity/customer_feedback_response_id_generator.dart';

/// An administrator responds to a [CustomerFeedback] ticket — manager-only
/// ([PosAuthorizedAction.manageCustomerFeedback]). Independent of status —
/// responding does not itself change [FeedbackStatus]/[FeedbackPriority]
/// (see `UpdateCustomerFeedbackStatus` for that).
class RespondToCustomerFeedback {
  const RespondToCustomerFeedback({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required CustomerFeedbackResponseIdGenerator idGenerator,
    required CustomerFeedbackRepository feedbackRepository,
    required CustomerFeedbackResponseRepository responseRepository,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _feedbackRepository = feedbackRepository,
        _responseRepository = responseRepository;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final CustomerFeedbackResponseIdGenerator _idGenerator;
  final CustomerFeedbackRepository _feedbackRepository;
  final CustomerFeedbackResponseRepository _responseRepository;

  Future<CustomerFeedbackResponse> call({
    required String feedbackId,
    required String responseText,
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

    final response = CustomerFeedbackResponse(
      id: _idGenerator.nextResponseId(),
      feedbackId: feedbackId,
      respondedByStaffId: performedByStaffId,
      responseText: responseText,
      respondedAt: _clock.now(),
    );
    await _responseRepository.append(response);
    return response;
  }
}
