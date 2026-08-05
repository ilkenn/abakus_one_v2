import '../domain/account_deletion_request.dart';

/// Storage for [AccountDeletionRequest] — mirrors every other repository
/// interface's shape in this codebase (`CustomerRepository`,
/// `StaffMemberRepository`, ...). Lives in `core/` (not a feature)
/// because it must be reachable from both `features/auth` (to block
/// sign-in during cooling-off) and `features/profile` (the request/
/// cancel UI) without introducing a second feature-to-feature import
/// exception — `core -> feature` and `feature -> feature` (beyond the
/// one documented auth↔crm exception) both stay forbidden;
/// `feature -> core` is always allowed.
abstract interface class AccountDeletionRequestRepository {
  Future<void> save(AccountDeletionRequest request);

  Future<AccountDeletionRequest?> findById(String requestId);

  /// The one active (not cancelled/completed) request for [uid], if any —
  /// "idempotent processing": a second `RequestAccountDeletion` call for
  /// the same [uid] finds this and returns it rather than creating a
  /// duplicate.
  Future<AccountDeletionRequest?> findActiveByUid(String uid);

  /// The most recent request for [uid] regardless of status, or `null` if
  /// none was ever made — what "is this account currently blocked from
  /// signing in" needs to check (`coolingOff`/`completed` both block;
  /// `cancelled` does not, and `findActiveByUid` alone can't answer that
  /// since it only ever returns non-terminal requests).
  Future<AccountDeletionRequest?> findLatestByUid(String uid);

  /// Every request currently in [AccountDeletionStatus.coolingOff] whose
  /// window has elapsed relative to [now] — what
  /// `ProcessAccountDeletion`/its Cloud Function equivalent consumes.
  Future<List<AccountDeletionRequest>> findDueForProcessing(DateTime now);
}

/// In-memory implementation — the only one this sprint (Sprint 9E's
/// "one pilot slice per sprint" discipline applies here too; a real
/// Firestore-backed implementation is future controlled migration work,
/// not attempted this sprint).
class InMemoryAccountDeletionRequestRepository
    implements AccountDeletionRequestRepository {
  final Map<String, AccountDeletionRequest> _byId = {};

  @override
  Future<void> save(AccountDeletionRequest request) async {
    _byId[request.id] = request;
  }

  @override
  Future<AccountDeletionRequest?> findById(String requestId) async =>
      _byId[requestId];

  @override
  Future<AccountDeletionRequest?> findActiveByUid(String uid) async {
    for (final request in _byId.values) {
      if (request.uid == uid &&
          (request.status == AccountDeletionStatus.pendingVerification ||
              request.status == AccountDeletionStatus.coolingOff)) {
        return request;
      }
    }
    return null;
  }

  @override
  Future<AccountDeletionRequest?> findLatestByUid(String uid) async {
    AccountDeletionRequest? latest;
    for (final request in _byId.values) {
      if (request.uid != uid) continue;
      if (latest == null || request.requestedAt.isAfter(latest.requestedAt)) {
        latest = request;
      }
    }
    return latest;
  }

  @override
  Future<List<AccountDeletionRequest>> findDueForProcessing(
      DateTime now) async {
    return List.unmodifiable(
      _byId.values.where((request) => request.isDue(now)),
    );
  }
}
