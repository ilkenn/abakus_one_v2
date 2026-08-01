/// Lifecycle status of an [AdminDeviceRegistration] — mirrors
/// `BranchStatus`/`StaffMemberStatus`'s reversible-vs-terminal shape:
/// `active`/`inactive` are reversible, `archived` is terminal (Phase 6L,
/// `docs/decisions.md` ADR-023).
enum AdminDeviceRegistrationStatus {
  active,
  inactive,
  archived,
}
