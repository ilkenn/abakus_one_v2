import 'entitlement_module.dart';
import 'entitlement_scope_type.dart';
import 'entitlement_status.dart';

/// One tenant's subscription grant for one [EntitlementModule] at one
/// scope — "has the tenant purchased this module?" — Phase 7
/// (`docs/decisions.md` ADR-024). No payment/billing engine exists
/// anywhere in this codebase; a grant here records the *result* of a
/// (today, manual/out-of-band) subscription decision, never processes a
/// payment itself. Mutable registry entity, mirroring `Branch`/
/// `StaffMember`: current shape is what matters, append-only history is
/// not required by the brief for this record type.
class EntitlementGrant {
  const EntitlementGrant({
    required this.id,
    required this.module,
    required this.scopeType,
    required this.scopeId,
    this.status = EntitlementStatus.trial,
    this.startsAt,
    this.expiresAt,
    this.graceEndsAt,
    this.postGraceDisabledModules = const [],
    required this.grantedByStaffId,
    required this.grantedAt,
    required this.revision,
  });

  final String id;
  final EntitlementModule module;
  final EntitlementScopeType scopeType;
  final String scopeId;
  final EntitlementStatus status;

  /// `null` means "effective immediately" — no future-dated activation
  /// configured.
  final DateTime? startsAt;

  /// `null` means "no expiry configured" — [status] alone (not a missing
  /// end date) is what makes a grant stop counting; see
  /// [isCurrentlyEntitled].
  final DateTime? expiresAt;

  /// AP-2 final wiring — mirrors `entitlementAdmin.ts`'s `graceEndsAt`:
  /// non-null only while [status] is [EntitlementStatus.grace], the exact
  /// moment `sweepExpiredEntitlementGracePeriods` will transition this
  /// grant to [EntitlementStatus.suspended].
  final DateTime? graceEndsAt;

  /// AP-2 final wiring — mirrors `entitlementAdmin.ts`'s
  /// `postGraceDisabledModules`. Data-only today on both the real backend
  /// and here — nothing enforces it yet (see that file's own doc comment);
  /// carried through purely for accurate display.
  final List<EntitlementModule> postGraceDisabledModules;

  final String grantedByStaffId;
  final DateTime grantedAt;
  final int revision;

  /// Whether this grant makes the tenant entitled *at* [at] — `status`
  /// must be [EntitlementStatus.active]/[EntitlementStatus.trial]/
  /// [EntitlementStatus.grace] (mirrors `requireModuleEntitlement`'s own
  /// entitled-status set exactly — grace still works, by design), and
  /// [at] must fall within `[startsAt, expiresAt]` where either bound is
  /// set (an unset bound never constrains that side). Deny-by-default: an
  /// [EntitlementStatus.suspended]/[EntitlementStatus.expired]/
  /// [EntitlementStatus.revoked] grant is never entitled regardless of
  /// date range.
  bool isCurrentlyEntitled(DateTime at) {
    final statusOk = status == EntitlementStatus.active ||
        status == EntitlementStatus.trial ||
        status == EntitlementStatus.grace;
    if (!statusOk) return false;
    if (startsAt != null && at.isBefore(startsAt!)) return false;
    if (expiresAt != null && at.isAfter(expiresAt!)) return false;
    return true;
  }

  EntitlementGrant copyWith({
    EntitlementStatus? status,
    DateTime? startsAt,
    bool clearStartsAt = false,
    DateTime? expiresAt,
    bool clearExpiresAt = false,
    required int revision,
  }) {
    return EntitlementGrant(
      id: id,
      module: module,
      scopeType: scopeType,
      scopeId: scopeId,
      status: status ?? this.status,
      startsAt: clearStartsAt ? null : (startsAt ?? this.startsAt),
      expiresAt: clearExpiresAt ? null : (expiresAt ?? this.expiresAt),
      grantedByStaffId: grantedByStaffId,
      grantedAt: grantedAt,
      revision: revision,
    );
  }
}
