import '../../errors/business_rule_violation.dart';
import '../data/account_deletion_request_repository.dart';
import '../domain/account_deletion_request.dart';

/// Cancels an in-cooling-off account-deletion request — Sprint 9G
/// (`docs/decisions.md` ADR-026). "Request cancellable after identity
/// verification": the caller is responsible for re-verifying the actor's
/// identity (e.g. requiring a fresh, still-valid `AuthSession`) *before*
/// invoking this — this use case only enforces the *window* half
/// (`AccountDeletionRequest.canCancelAt`), not the identity check itself,
/// for the same `core -> feature` layering reason `RequestAccountDeletion`
/// documents.
class CancelAccountDeletionRequest {
  const CancelAccountDeletionRequest({
    required AccountDeletionRequestRepository repository,
  }) : _repository = repository;

  final AccountDeletionRequestRepository _repository;

  Future<AccountDeletionRequest> call({
    required String requestId,
    required DateTime now,
  }) async {
    final request = await _repository.findById(requestId);
    if (request == null || !request.canCancelAt(now)) {
      throw AccountDeletionRequestNotCancellableViolation(
        requestId: requestId,
      );
    }

    final cancelled = request.copyWith(
      status: AccountDeletionStatus.cancelled,
      cancelledAt: now,
      revision: request.revision + 1,
    );
    await _repository.save(cancelled);
    return cancelled;
  }
}
