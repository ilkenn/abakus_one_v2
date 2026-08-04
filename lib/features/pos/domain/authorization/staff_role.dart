/// The role tiers [RealPosAuthorizationPolicy] recognizes — Sprint 5E,
/// extended Phase 8 (`docs/decisions.md` ADR-025). A person may hold
/// more than one ([ActorSession.roles] is a set, not a single value) —
/// a courier who is also a shift manager holds both [courier] and
/// [manager].
///
/// [courier] is a lateral, non-hierarchical tier (a courier's own
/// delivery-lifecycle actions only). [staff] < [manager] < [admin] <
/// [tenantOwner] is a strict hierarchy — [RolePermissionMap.permissionsFor]
/// grants each higher tier everything the tier(s) below it can do, plus
/// its own additional actions, so `admin` never has to duplicate
/// `manager`'s or `staff`'s entries by hand, and `tenantOwner` never
/// duplicates `admin`'s.
///
/// **[tenantOwner] is still a *tenant*-hierarchy role** — every value in
/// this enum, including [tenantOwner], operates within one
/// `organizationId` (see [ActorSession.organizationAccess]), never
/// across tenants. Cross-tenant platform actions are a wholly separate
/// stack (`features/platform/domain/authorization/platform_role.dart`)
/// — see that file's own doc comment for why the two are never merged.
enum StaffRole { courier, staff, manager, admin, tenantOwner }
