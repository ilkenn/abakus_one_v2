/// The role tiers [RealPlatformAuthorizationPolicy] recognizes — Phase 8
/// (`docs/decisions.md` ADR-025).
///
/// Deliberately a wholly separate enum from `StaffRole`
/// (`features/pos/domain/authorization/staff_role.dart`), not an
/// extension of it: "Platform Owner remains completely separated from
/// tenant hierarchy" (the Phase 8 kickoff's own explicit requirement)
/// is enforced by construction here — nothing in this file imports or
/// references any tenant-hierarchy type, so a platform actor can never
/// be confused with, or accidentally checked against, tenant-scoped
/// authorization.
///
/// [platformAdministrator] < [platformOwner] — a strict hierarchy, the
/// same shape `StaffRole`'s staff/manager/admin tiering already
/// established (see `PlatformRolePermissionMap.permissionsFor`).
enum PlatformRole { platformAdministrator, platformOwner }
