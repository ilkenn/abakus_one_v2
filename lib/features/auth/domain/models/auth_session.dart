/// A persisted authentication session. [uid] is the canonical, immutable
/// identity — Phase 9 (`docs/decisions.md` ADR-026) — issued by Firebase
/// Auth (real project or, in development, the local Auth Emulator; both
/// issue genuine, stable UIDs, never a client-fabricated string). Every
/// other identity in the app (`ProfileModel.id`, CRM `Customer.id`,
/// `Order.customerId`) links back to this same value — see
/// `ResolveCurrentCustomer` and `profileProvider`. [phoneNumber] remains a
/// verified login/lookup attribute, never the permanent identity itself.
class AuthSession {
  final String uid;
  final String phoneNumber;
  final DateTime createdAt;
  final DateTime expiresAt;

  const AuthSession({
    required this.uid,
    required this.phoneNumber,
    required this.createdAt,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'phoneNumber': phoneNumber,
        'createdAt': createdAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
      };

  /// Returns `null` instead of throwing when [json] is missing a required
  /// field or malformed — callers (see `SecureSessionStorage.readSession`)
  /// treat `null` as "no valid session," never as a crash. A session
  /// persisted before Sprint 9C (no `uid` field) also decodes to `null` here
  /// deliberately: there is no real user data behind it (greenfield, no
  /// production traffic yet — `docs/decisions.md` ADR-026), so the safe,
  /// simple upgrade path is "sign in again," not a silent identity
  /// fabrication.
  static AuthSession? tryFromJson(Map<String, dynamic> json) {
    final uid = json['uid'];
    final phoneNumber = json['phoneNumber'];
    final createdAtRaw = json['createdAt'];
    final expiresAtRaw = json['expiresAt'];
    if (uid is! String ||
        phoneNumber is! String ||
        createdAtRaw is! String ||
        expiresAtRaw is! String) {
      return null;
    }
    final createdAt = DateTime.tryParse(createdAtRaw);
    final expiresAt = DateTime.tryParse(expiresAtRaw);
    if (createdAt == null || expiresAt == null) {
      return null;
    }
    return AuthSession(
      uid: uid,
      phoneNumber: phoneNumber,
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
  }
}
