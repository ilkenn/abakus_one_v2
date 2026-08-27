import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../bootstrap/firebase_ready_provider.dart';
import '../../../../core/services/feature_flags/feature_flags_provider.dart';
import '../../../pos/presentation/providers/actor_session_provider.dart';
import '../../application/identity/entitlement_grant_id_generator.dart';
import '../../application/use_cases/check_module_access.dart';
import '../../data/entitlement_audit_entry_repository.dart';
import '../../data/entitlement_grant_repository.dart';
import '../../data/firebase_entitlement_grant_repository.dart';
import '../../domain/entitlement_grant.dart';
import '../../domain/entitlement_module.dart';
import '../../domain/entitlement_scope_type.dart';
import '../../domain/entitlement_status.dart';

/// Central Riverpod wiring for `features/entitlements` — Phase 7
/// (`docs/decisions.md` ADR-024), mirrors `admin_dependencies_provider
/// .dart`'s shape.
///
/// Seeded with an active grant for **every** Phase 7 module at the
/// existing single seeded branch (`'branch-1'`, from Phase 6D) — this is
/// the platform's own real, single tenant today, not a demonstration of
/// "everyone gets everything free": the corresponding feature flags
/// (`FeatureFlagsKeys.inventoryEnabled` etc.) still all default `false`,
/// so a module remains invisible until both axes agree, matching how
/// this codebase's five pre-Phase-7 flags already default off for
/// unshipped functionality.
///
/// Deliberately NOT swapped to the real Firestore-backed repository when
/// Firebase is ready, unlike most other AP-2-final-wiring providers — this
/// one backs [checkModuleAccessProvider]/`ModuleEntitlementGate`, consumed
/// across the ENTIRE Admin app, not only the Entitlements screen. Doing so
/// would mean every other already-visible module gate starts reading real
/// (today, empty) `entitlements` docs the moment Firebase is ready, hiding
/// features app-wide with no real grants seeded yet — a much wider blast
/// radius than "wire the Entitlement Admin UI" calls for. See
/// [entitlementGrantReadRepositoryProvider] below for the real,
/// Firestore-backed, read-only repository the Admin/Platform-Owner
/// screens use instead — a deliberately separate seam, not a shared one.
final entitlementGrantRepositoryProvider =
    Provider<EntitlementGrantRepository>((ref) {
  final now = DateTime(2026, 1, 1);
  return InMemoryEntitlementGrantRepository(
    seed: [
      for (var i = 0; i < EntitlementModule.values.length; i++)
        EntitlementGrant(
          id: 'entitlement-seed-${i + 1}',
          module: EntitlementModule.values[i],
          scopeType: EntitlementScopeType.branch,
          scopeId: 'branch-1',
          status: EntitlementStatus.active,
          grantedByStaffId: 'system',
          grantedAt: now,
          revision: 1,
        ),
    ],
  );
});

/// AP-2 final wiring — the real, `entitlements`-collection-backed,
/// read-only repository (see [FirestoreEntitlementGrantRepository]'s own
/// doc comment on why `save` throws). Used ONLY by
/// [EntitlementAdminScreen]'s real view and the Platform Owner console —
/// never by [checkModuleAccessProvider] (see [entitlementGrantRepositoryProvider]'s
/// own doc comment for why that stays separate). Falls back to an
/// explicit "unavailable" implementation (fails closed with a real error,
/// never a silent empty list) when Firebase isn't ready.
final entitlementGrantReadRepositoryProvider =
    Provider<EntitlementGrantRepository>((ref) {
  final isFirebaseReady = ref.watch(firebaseReadyProvider);
  if (isFirebaseReady) {
    return FirestoreEntitlementGrantRepository();
  }
  return const UnavailableEntitlementGrantRepository();
});

final entitlementGrantIdGeneratorProvider =
    Provider<EntitlementGrantIdGenerator>((ref) {
  return SequentialEntitlementGrantIdGenerator();
});

final entitlementAuditEntryRepositoryProvider =
    Provider<EntitlementAuditEntryRepository>((ref) {
  return InMemoryEntitlementAuditEntryRepository();
});

final checkModuleAccessProvider = Provider<CheckModuleAccess>((ref) {
  return CheckModuleAccess(
    entitlementRepository: ref.watch(entitlementGrantRepositoryProvider),
    featureFlagsService: ref.watch(featureFlagsServiceProvider),
    authorizationPolicy: ref.watch(posAuthorizationPolicyProvider),
  );
});
