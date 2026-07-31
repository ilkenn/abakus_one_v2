/// The role tiers [RealPosAuthorizationPolicy] recognizes — Sprint 5E.
/// A person may hold more than one ([ActorSession.roles] is a set, not a
/// single value) — a courier who is also a shift manager holds both
/// [courier] and [manager].
///
/// [courier] is a lateral, non-hierarchical tier (a courier's own
/// delivery-lifecycle actions only). [staff] < [manager] < [admin] is a
/// strict hierarchy — [RolePermissionMap.permissionsFor] grants each
/// higher tier everything the tier(s) below it can do, plus its own
/// additional actions, so `admin` never has to duplicate `manager`'s or
/// `staff`'s entries by hand.
enum StaffRole { courier, staff, manager, admin }
