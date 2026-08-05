import '../data/account_deletion_request_repository.dart';
import '../domain/account_deletion_request.dart';
import 'account_deletion_request_id_generator.dart';

/// Creates (or idempotently returns an already-active) account-deletion
/// request for [uid] — Sprint 9G (`docs/decisions.md` ADR-026). The
/// default 7-day cooling-off period is the user-approved policy this
/// sprint implements verbatim, not a value this use case chose on its
/// own.
///
/// Transitions straight from [AccountDeletionStatus.pendingVerification]
/// to [AccountDeletionStatus.coolingOff] within this one call — see
/// [AccountDeletionStatus]'s own doc comment for why: the caller must
/// already hold a valid authenticated session to reach this use case,
/// which is this sprint's identity verification for *requesting*
/// deletion (stronger re-verification is required to *cancel* — see
/// `CancelAccountDeletionRequest`).
///
/// **Idempotent**: a second call for the same [uid] while a request is
/// already active (`pendingVerification`/`coolingOff`) returns the
/// existing request unchanged rather than creating a duplicate.
///
/// Does **not** itself revoke the caller's session — that is an
/// orchestration step the caller (a `features/profile` provider) is
/// responsible for immediately after this returns, since `core/` must
/// never depend on `features/auth` (`CLAUDE.md` §3's `core -> feature`
/// prohibition).
class RequestAccountDeletion {
  const RequestAccountDeletion({
    required AccountDeletionRequestRepository repository,
    required AccountDeletionRequestIdGenerator idGenerator,
    this.coolingOffPeriod = const Duration(days: 7),
  })  : _repository = repository,
        _idGenerator = idGenerator;

  final AccountDeletionRequestRepository _repository;
  final AccountDeletionRequestIdGenerator _idGenerator;
  final Duration coolingOffPeriod;

  Future<AccountDeletionRequest> call({
    required String uid,
    required DateTime now,
  }) async {
    final existing = await _repository.findActiveByUid(uid);
    if (existing != null) return existing;

    final request = AccountDeletionRequest(
      id: _idGenerator.nextRequestId(),
      uid: uid,
      status: AccountDeletionStatus.coolingOff,
      requestedAt: now,
      coolingOffEndsAt: now.add(coolingOffPeriod),
      revision: 1,
    );
    await _repository.save(request);
    return request;
  }
}
