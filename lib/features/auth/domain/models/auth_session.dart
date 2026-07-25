/// A persisted authentication session — deliberately minimal until a real
/// backend exists (see `AuthRepository`'s doc comment for why). No fake
/// access/refresh token is fabricated here; [phoneNumber] plus a bounded
/// local validity window ([expiresAt]) are enough to answer "is this
/// session still good" for the development-only auth flow this app has
/// today.
class AuthSession {
  final String phoneNumber;
  final DateTime createdAt;
  final DateTime expiresAt;

  const AuthSession({
    required this.phoneNumber,
    required this.createdAt,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toJson() => {
        'phoneNumber': phoneNumber,
        'createdAt': createdAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
      };

  /// Returns `null` instead of throwing when [json] is missing a required
  /// field or malformed — callers (see `SecureSessionStorage.readSession`)
  /// treat `null` as "no valid session," never as a crash.
  static AuthSession? tryFromJson(Map<String, dynamic> json) {
    final phoneNumber = json['phoneNumber'];
    final createdAtRaw = json['createdAt'];
    final expiresAtRaw = json['expiresAt'];
    if (phoneNumber is! String ||
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
      phoneNumber: phoneNumber,
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
  }
}
