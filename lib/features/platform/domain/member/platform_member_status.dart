/// A [PlatformMember]'s account lifecycle state — Phase 8
/// (`docs/decisions.md` ADR-025). Mirrors `StaffMemberStatus`'s exact
/// reversible/terminal distinction.
enum PlatformMemberStatus { active, suspended, archived }
