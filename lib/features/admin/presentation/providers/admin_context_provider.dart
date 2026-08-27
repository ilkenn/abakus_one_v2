import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_dependencies_provider.dart';

/// AP-2 closure correction — one organization the signed-in staff actor's
/// own real memberships grant access to, with the exact branches/roles
/// that membership carries. Mirrors `resolveActorContext`'s own response
/// shape one-to-one; the raw `List<Map<String, dynamic>>`
/// [resolvedActorContextProvider] exposes at the wire level is parsed into
/// this typed model here, once, so the switcher UI/tests never touch a
/// bare map.
class ActorOrganizationAccess {
  const ActorOrganizationAccess({
    required this.organizationId,
    required this.roles,
    required this.branchIds,
  });

  final String organizationId;
  final List<String> roles;
  final List<String> branchIds;

  factory ActorOrganizationAccess.fromMap(Map<String, dynamic> map) {
    return ActorOrganizationAccess(
      organizationId: map['organizationId'] as String,
      roles: List<String>.from(map['roles'] as List),
      branchIds: List<String>.from(map['branchIds'] as List),
    );
  }
}

/// The typed form of [resolvedActorContextProvider] — a real,
/// backend-verified (`resolveActorContext`, never client-supplied)
/// enumeration of every organization/branch the caller's own ACTIVE
/// memberships currently grant. Re-fetches fresh (not cached) every time
/// it's watched/refreshed — the context switcher relies on this to detect
/// a revoked membership or removed branch access on its own next open,
/// never trusting a value it read once and held onto.
final typedActorContextProvider =
    FutureProvider<List<ActorOrganizationAccess>>((ref) async {
  final raw = await ref.watch(resolvedActorContextProvider.future);
  return raw.map(ActorOrganizationAccess.fromMap).toList();
});

/// AP-2 closure correction — when non-null, the currently active trusted
/// device is bound to exactly this branch (`trustedDeviceRegistrations`'
/// own `branchId` field, server-side) and the context switcher must not
/// allow switching to any other branch while device-restricted operation
/// is active. Defaults to `null` (no Flutter-side trusted-device session
/// UI exists yet this phase — see AP-2's own closure report for this
/// disclosed boundary) — the GUARD itself is real and tested; the trusted-
/// device Flutter integration that would ever set this to a real value is
/// separate, later work.
final deviceBoundBranchIdProvider = Provider<String?>((ref) => null);
