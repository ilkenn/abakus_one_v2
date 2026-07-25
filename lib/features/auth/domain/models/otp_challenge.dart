/// The set of outcomes verifying an OTP code can produce. Kept as a plain
/// enum — three cases, no payload beyond the case itself — rather than a
/// class hierarchy, per the explicit instruction not to over-engineer this.
enum OtpVerificationResult { success, invalidCode, expired }

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
