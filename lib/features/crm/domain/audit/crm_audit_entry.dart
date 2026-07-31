import 'crm_audit_event_type.dart';

/// One immutable, append-only audit record of a CRM/Loyalty mutation —
/// **Sprint 5E Part 6** (`docs/decisions.md` ADR-022), closing the
/// "zero audit-trail coverage" gap the Phase 5 architecture review found
/// in `features/crm` (Feedback already had an equivalent structurally,
/// via `CustomerFeedbackStatusEvent`/`CustomerFeedbackResponse` — no new
/// type was needed there).
///
/// **A deliberately separate type from `CourierOperationalAuditEntry`**,
/// not a reused/shared one — same shape and reasoning (actor, actor
/// role, timestamp, target entity, previous/new state, an immutable
/// append-only record), but CRM has no delivery/courier/shift/
/// assignment concepts to carry, and importing the courier feature's
/// audit infrastructure into `features/crm` would be exactly the
/// cross-domain coupling the brief said to avoid.
///
/// **[branchId] is `null` for entity types with no single-branch scope**
/// (a `VisitRewardRule`/`Survey`/`CustomerNotificationCampaign` may
/// apply to multiple branches or none at all) — "branch scope where
/// available," not invented where it doesn't structurally exist.
class CrmAuditEntry {
  const CrmAuditEntry({
    required this.id,
    this.branchId,
    required this.actorId,
    this.actorRole,
    required this.type,
    required this.description,
    required this.targetEntityId,
    this.previousStateName,
    this.newStateName,
    required this.timestamp,
  });

  final String id;
  final String? branchId;

  /// The staff/customer/system actor id — never a hardcoded literal;
  /// always the caller-supplied id that actually performed the action.
  /// `'system'` is the one documented sentinel, used only where no human
  /// actor exists (an automated orchestration step — see
  /// `RecordCustomerVisitAndEvaluateRewards`'s own doc comment).
  final String actorId;

  /// Free-text role label (e.g. `'customer'`, `'manager'`, `'system'`) —
  /// nullable, matching `CourierOperationalAuditEntry.actorRole`'s own
  /// shape, since not every caller has a resolved `StaffRole` to supply.
  final String? actorRole;

  final CrmAuditEventType type;
  final String description;
  final String targetEntityId;
  final String? previousStateName;
  final String? newStateName;
  final DateTime timestamp;
}
