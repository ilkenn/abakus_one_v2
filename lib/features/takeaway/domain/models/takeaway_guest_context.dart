/// The customer app's "current Gel Al QR guest session" state — Faz D.4.
/// Mirrors `ActiveTableContext`'s role for the dine-in-QR flow, but
/// deliberately lean: no wrapped legacy `TableSession`/`GuestSession`
/// objects (nothing else in the app depends on such a shape for
/// takeaway), and no `tableId`/`tableName` (a takeaway QR belongs to a
/// branch, not a table).
///
/// Client-side-only — the server independently re-verifies session
/// ownership/liveness (`guestAuthUid`/`status`/`expiresAt`) on every
/// `submitTakeawayOrder` call regardless of what this object says; this
/// exists to drive UI (branch name, session-expiry countdown/guard), not
/// as an authorization source.
class TakeawayGuestContext {
  final String sessionId;
  final String organizationId;
  final String restaurantId;
  final String branchId;
  final String branchDisplayName;
  final DateTime expiresAt;

  /// The Firebase Auth uid this session is bound to — the exact value
  /// `TechnicalIdentityProvider.ensureSignedIn()` returned when the
  /// session was opened. Never a normal Abaküs customer account; see
  /// `TechnicalIdentityProvider`'s own doc comment.
  final String guestAuthUid;

  const TakeawayGuestContext({
    required this.sessionId,
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.branchDisplayName,
    required this.expiresAt,
    required this.guestAuthUid,
  });

  /// Client-side-only convenience — the server independently re-checks
  /// this at submit time (`submitTakeawayOrder`'s guest branch), which
  /// remains the actual authority. Used here only to show a friendly
  /// "session expired, rescan the QR" state instead of letting the user
  /// submit and hit a raw server error.
  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);

  TakeawayGuestContext copyWith({
    String? sessionId,
    String? organizationId,
    String? restaurantId,
    String? branchId,
    String? branchDisplayName,
    DateTime? expiresAt,
    String? guestAuthUid,
  }) {
    return TakeawayGuestContext(
      sessionId: sessionId ?? this.sessionId,
      organizationId: organizationId ?? this.organizationId,
      restaurantId: restaurantId ?? this.restaurantId,
      branchId: branchId ?? this.branchId,
      branchDisplayName: branchDisplayName ?? this.branchDisplayName,
      expiresAt: expiresAt ?? this.expiresAt,
      guestAuthUid: guestAuthUid ?? this.guestAuthUid,
    );
  }
}
