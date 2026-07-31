/// A [StaffMember]'s account lifecycle state — Phase 6B/6C
/// (`docs/decisions.md` ADR-023).
///
/// [suspended]/[archived] are both terminal to signing in (see
/// `StaffAuthRepository`), but distinct: [suspended] is reversible (a
/// manager/admin can reinstate), [archived] is not — mirrors
/// `CourierAvailabilityStatus`'s reversible-vs-terminal distinction.
enum StaffMemberStatus { active, suspended, archived }
