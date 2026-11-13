/// A [StaffMember]'s account lifecycle state — Phase 6B/6C
/// (`docs/decisions.md` ADR-023).
///
/// [suspended]/[archived] are both terminal to signing in (see
/// `StaffAuthRepository`), but distinct: [suspended] is reversible (a
/// manager/admin can reinstate), [archived] is not — mirrors
/// `CourierAvailabilityStatus`'s reversible-vs-terminal distinction.
///
/// ADR-085 stage 1 — [pendingApproval]: added by a manager, waiting for an
/// admin/owner in the Onay Kutusu; cannot sign in to the panel until then.
/// Only the server ever sets it.
enum StaffMemberStatus { active, suspended, archived, pendingApproval }
