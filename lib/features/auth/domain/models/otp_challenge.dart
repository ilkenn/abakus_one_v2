/// The set of outcomes verifying an OTP code can produce. Kept as a plain
/// enum — no payload beyond the case itself — rather than a class
/// hierarchy, per the explicit instruction not to over-engineer this.
///
/// [accountBlocked] — Sprint 9G (`docs/decisions.md` ADR-026): the code
/// itself was correct, but the account has an active/completed account-
/// deletion request (`AuthNotifier._isBlockedByDeletionRequest`) and
/// sign-in was refused for that reason — kept distinct from
/// [invalidCode] so the UI never tells a user their *correct* code was
/// wrong.
enum OtpVerificationResult { success, invalidCode, expired, accountBlocked }

/// An outstanding OTP challenge for one phone number. Correctness/expiry
/// evaluation lives on the repository that issues and checks these — see
/// `AuthRepository`'s doc comment — this class is just the data shape, not
/// where "is this code right" gets decided.
class OtpChallenge {
  final String phoneNumber;
  final DateTime issuedAt;
  final DateTime expiresAt;

  const OtpChallenge({
    required this.phoneNumber,
    required this.issuedAt,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
