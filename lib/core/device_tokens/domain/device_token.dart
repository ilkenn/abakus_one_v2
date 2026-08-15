/// An FCM device token registered for push notifications — Sprint 9H
/// (`docs/decisions.md` ADR-026). Mirrors `docs/firestore_data_model.md`'s
/// `deviceTokens/{tokenId}` collection ("the owning user, their own
/// tokens only"). Lives in `core/` (not a feature) for the same reason
/// `core/account_deletion` does — device-token ownership is a
/// cross-cutting identity concern, not one feature's own detail.
///
/// **Scope, stated honestly**: this is the registration/ownership record
/// only. Actual push delivery, quiet-hours suppression, delivery-status
/// tracking, and deep-link payload versioning are explicitly deferred —
/// see `docs/decisions.md` ADR-026 Decision 9's "not yet implemented"
/// list.
class DeviceToken {
  const DeviceToken({
    required this.id,
    required this.uid,
    required this.organizationId,
    required this.token,
    required this.platform,
    required this.registeredAt,
    this.revokedAt,
  });

  final String id;
  final String uid;

  /// Faz R.3C: added to satisfy `firestore.rules`'s pre-existing
  /// `deviceTokens` `organizationIdUnchanged()` update check, which
  /// expected this field before any Firestore-backed repository actually
  /// wrote it — mirrors the single-tenant `currentOrganizationIdProvider`
  /// convention (`core/config/current_organization.dart`).
  final String organizationId;

  /// The raw FCM registration token — opaque to this app, never logged
  /// (mirrors `LogRedactor`'s "token" marker — any future logging of a
  /// `DeviceToken` must redact this field the same way).
  final String token;

  /// `'android'` / `'ios'` / `'web'` — free-form for now (no enum yet;
  /// the three-platform set this app already targets in
  /// `firebase_options*.dart`).
  final String platform;

  final DateTime registeredAt;

  /// Set when the token is invalidated (user signed out, app
  /// uninstalled/token refreshed) — a revoked token is never deleted
  /// outright, so "this token used to belong to this user" stays
  /// auditable, mirroring this codebase's general append-first-then-mark
  /// convention rather than hard deletion.
  final DateTime? revokedAt;

  bool get isActive => revokedAt == null;

  DeviceToken copyWith({DateTime? revokedAt}) {
    return DeviceToken(
      id: id,
      uid: uid,
      organizationId: organizationId,
      token: token,
      platform: platform,
      registeredAt: registeredAt,
      revokedAt: revokedAt ?? this.revokedAt,
    );
  }
}
