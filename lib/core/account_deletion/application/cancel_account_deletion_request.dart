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
///
/// **[uid] ownership check — closed during this phase's mandatory
/// adversarial security review**: the first version of this use case
/// accepted a bare `requestId` with no verification that the caller
/// actually owns the request being cancelled — an IDOR class gap (any
/// caller who learned/guessed another user's `requestId` could cancel
/// *their* deletion). [uid] is now required and checked against
/// [AccountDeletionRequest.uid] before anything else; a mismatch is
/// reported identically to "not found"/"not cancellable" — never
/// distinguishing "this request exists but isn't yours" from "this
/// request doesn't exist," so the error itself leaks nothing.
class CancelAccountDeletionRequest {
  const CancelAccountDeletionRequest({
    required AccountDeletionRequestRepository repository,
  }) : _repository = repository;

  final AccountDeletionRequestRepository _repository;

  Future<AccountDeletionRequest> call({
    required String requestId,
    required String uid,
    required DateTime now,
  }) async {
    final request = await _repository.findById(requestId);
    if (request == null || request.uid != uid || !request.canCancelAt(now)) {
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
