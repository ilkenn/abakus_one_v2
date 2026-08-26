import 'package:cloud_functions/cloud_functions.dart' as functions;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../bootstrap/firebase_ready_provider.dart';
import '../../../../core/services/auth/email_password_auth_client.dart';
import '../../../../core/services/auth/staff_claims_sync_client.dart';
import '../../data/firebase_staff_member_repository.dart';
import '../../../courier/presentation/providers/courier_core_dependencies_provider.dart';
import '../../../pos/presentation/providers/kds_dependencies_provider.dart';
import '../../../restaurant/presentation/providers/restaurant_operations_dependencies_provider.dart';
import '../../application/identity/admin_device_registration_id_generator.dart';
import '../../application/identity/branch_id_generator.dart';
import '../../application/identity/customer_admin_note_id_generator.dart';
import '../../application/identity/customer_photo_id_generator.dart';
import '../../application/identity/localization_config_id_generator.dart';
import '../../application/identity/organization_id_generator.dart';
import '../../application/identity/restaurant_id_generator.dart';
import '../../application/identity/staff_member_id_generator.dart';
import '../../application/identity/staff_role_change_event_id_generator.dart';
import '../../application/identity/translation_entry_id_generator.dart';
import '../../application/use_cases/build_audit_center_projection.dart';
import '../../application/use_cases/build_device_registry_projection.dart';
import '../../data/admin_audit_entry_repository.dart';
import '../../data/admin_device_registration_repository.dart';
import '../../data/branch_repository.dart';
import '../../data/customer_admin_note_repository.dart';
import '../../data/customer_photo_repository.dart';
import '../../data/localization_config_repository.dart';
import '../../data/maintenance_mode_state_repository.dart';
import '../../data/organization_repository.dart';
import '../../data/restaurant_repository.dart';
import '../../data/staff_auth_repository.dart';
import '../../data/staff_member_repository.dart';
import '../../data/staff_role_change_event_repository.dart';
import '../../data/translation_entry_repository.dart';
import '../../domain/organization/branch.dart';
import '../../domain/organization/organization.dart';
import '../../domain/organization/restaurant.dart';

/// Central Riverpod wiring for `features/admin` — mirrors
/// `crm_dependencies_provider.dart`'s shape (Phase 6, `docs/decisions.md`
/// ADR-023).
///
/// AP-2 Stage B — [firebaseReadyProvider] now selects the real,
/// `listStaffMembersForOrganization`-backed [FirebaseStaffMemberRepository]
/// (mirrors `staffAuthRepositoryProvider`'s own exact gate one tier up).
/// `kReleaseMode` remains the fallback gate when Firebase isn't ready —
/// Phase 8 closure sprint's (`docs/decisions.md` ADR-025) "the roster
/// itself must never be available in Release" still holds: a release
/// build with no healthy Firebase connection gets
/// [ProductionUnavailableStaffMemberRepository], never the in-memory
/// stand-in.
final staffMemberRepositoryProvider = Provider<StaffMemberRepository>((ref) {
  final isFirebaseReady = ref.watch(firebaseReadyProvider);
  if (isFirebaseReady) {
    return FirebaseStaffMemberRepository(
      organizationId: () => ref.read(currentOrganizationIdProvider),
    );
  }
  if (kReleaseMode) {
    return const ProductionUnavailableStaffMemberRepository();
  }
  return InMemoryStaffMemberRepository();
});

final staffRoleChangeEventRepositoryProvider =
    Provider<StaffRoleChangeEventRepository>((ref) {
  return InMemoryStaffRoleChangeEventRepository();
});

final adminAuditEntryRepositoryProvider =
    Provider<AdminAuditEntryRepository>((ref) {
  return InMemoryAdminAuditEntryRepository();
});

final staffMemberIdGeneratorProvider = Provider<StaffMemberIdGenerator>((ref) {
  return SequentialStaffMemberIdGenerator();
});

final staffRoleChangeEventIdGeneratorProvider =
    Provider<StaffRoleChangeEventIdGenerator>((ref) {
  return SequentialStaffRoleChangeEventIdGenerator();
});

/// [firebaseReadyProvider] selects the fail-closed implementation — Sprint
/// 9C (`docs/decisions.md` ADR-026), superseding the previous
/// `kReleaseMode` split, exactly mirroring `authRepositoryProvider`'s own
/// gate (`features/auth`). "Do not claim production backend validation if
/// none exists" — now genuinely satisfied: a healthy Firebase connection
/// means real credential-checked sign-in in every build, not just debug.
final staffAuthRepositoryProvider = Provider<StaffAuthRepository>((ref) {
  final isFirebaseReady = ref.watch(firebaseReadyProvider);
  if (!isFirebaseReady) {
    return const ProductionUnavailableStaffAuthRepository();
  }
  return FirebaseStaffAuthRepository(
    authClient: DefaultEmailPasswordAuthClient(),
    staffMemberRepository: ref.watch(staffMemberRepositoryProvider),
    sessionDuration: () => const Duration(hours: 12),
    claimsSyncClient: DefaultStaffClaimsSyncClient(),
    // Faz R.3A.2 — the same organization this admin app instance serves,
    // resolved once here rather than re-declared as a second literal
    // inside the repository.
    organizationId: () => ref.read(currentOrganizationIdProvider),
  );
});

// Phase 6D — organization/restaurant/branch minimum tenant boundary.
// Seeded with exactly one Organization/Restaurant/Branch whose id
// matches `currentBranchIdProvider`'s pre-existing `'branch-1'` literal
// (`features/navigation`) — "preserve existing branchId references":
// every one of the 177 existing bare-`String` `branchId` call sites
// across courier/POS/CRM/feedback/restaurant keeps resolving to the
// same id, now backed by a real, admin-manageable `Branch` record
// instead of nothing.
final organizationRepositoryProvider = Provider<OrganizationRepository>((ref) {
  return InMemoryOrganizationRepository(seed: [
    Organization(
      id: 'org-1',
      name: 'Abaküs',
      createdAt: DateTime(2026, 1, 1),
      revision: 1,
    ),
  ]);
});

/// The tenant the currently running app instance serves — Phase 8
/// (`docs/decisions.md` ADR-025). **Still a placeholder default, not real
/// tenant selection**: this app has no tenant-switching UI anywhere yet
/// (no screen lets an actor pick which organization's build they're
/// running), so this always resolves to the single seeded organization
/// above — mirrors `currentBranchIdProvider`'s exact honest-placeholder
/// pattern (`features/navigation`) for the same reason. Building a real
/// tenant-switcher UI remains separate, unrelated feature work.
///
/// **AP-2 Stage B — this is genuinely safe to leave as a client-side
/// default now, in a way it wasn't before**: every AP-2 backend command
/// this value ever gets passed into (`resolveVerifiedBranchContext` and
/// everything built on it) treats it strictly as an untrusted LOCATOR,
/// re-verified against the caller's own real durable membership
/// server-side — a stale or wrong value here can only ever cause a
/// `permission-denied`, never a cross-tenant authorization bypass. See
/// [resolvedActorContextProvider] for the real, callable-backed
/// enumeration a future context-switcher UI would build on.
final currentOrganizationIdProvider = Provider<String>((ref) => 'org-1');

/// AP-2 Stage B — the real, self-derived enumeration of every organization/
/// branch/role the SIGNED-IN STAFF ACTOR's own active memberships actually
/// grant (`resolveActorContext`, never client-supplied). Not yet consumed
/// by any screen (no context-switcher UI exists yet — see
/// [currentOrganizationIdProvider]'s own doc comment) — this provider
/// exists so that UI is real, callable-backed work whenever it's built,
/// rather than a second placeholder layered on top of the first.
final resolvedActorContextProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final isFirebaseReady = ref.watch(firebaseReadyProvider);
  if (!isFirebaseReady) return const [];
  final callable =
      functions.FirebaseFunctions.instance.httpsCallable('resolveActorContext');
  final result = await callable.call<Map<String, dynamic>>();
  return List<Map<String, dynamic>>.from(
    (result.data['organizations'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map)),
  );
});

final restaurantRepositoryProvider = Provider<RestaurantRepository>((ref) {
  return InMemoryRestaurantRepository(seed: [
    Restaurant(
      id: 'restaurant-1',
      organizationId: 'org-1',
      name: 'Abaküs Bowl',
      createdAt: DateTime(2026, 1, 1),
      revision: 1,
    ),
  ]);
});

final branchRepositoryProvider = Provider<BranchRepository>((ref) {
  return InMemoryBranchRepository(seed: [
    Branch(
      id: 'branch-1',
      restaurantId: 'restaurant-1',
      name: 'Merkez Şube',
      // Corrected, Faz C (Gel Al architecture analysis): this branch
      // already genuinely serves dineInQr/dineInStaff/delivery today
      // (real, tested customer-app flows) — the seed literal simply never
      // declared that until a real caller (`ListTakeawayEligibleBranches`)
      // needed to check `supportedOrderChannelIds` for the first time.
      // `reservationPreorder` stays excluded — that flow is still an
      // explicit "coming soon" placeholder (`home_screen.dart`).
      supportedOrderChannelIds: const {
        'dineInQr',
        'dineInStaff',
        'delivery',
        'takeaway',
      },
      createdAt: DateTime(2026, 1, 1),
      revision: 1,
    ),
  ]);
});

final organizationIdGeneratorProvider =
    Provider<OrganizationIdGenerator>((ref) {
  return SequentialOrganizationIdGenerator();
});

final restaurantIdGeneratorProvider = Provider<RestaurantIdGenerator>((ref) {
  return SequentialRestaurantIdGenerator();
});

final branchIdGeneratorProvider = Provider<BranchIdGenerator>((ref) {
  return SequentialBranchIdGenerator();
});

// Phase 6F — customer admin notes/risk flags.
final customerAdminNoteRepositoryProvider =
    Provider<CustomerAdminNoteRepository>((ref) {
  return InMemoryCustomerAdminNoteRepository();
});

final customerAdminNoteIdGeneratorProvider =
    Provider<CustomerAdminNoteIdGenerator>((ref) {
  return SequentialCustomerAdminNoteIdGenerator();
});

// Phase 6G — customer photo moderation.
final customerPhotoRepositoryProvider =
    Provider<CustomerPhotoRepository>((ref) {
  return InMemoryCustomerPhotoRepository();
});

final customerPhotoIdGeneratorProvider =
    Provider<CustomerPhotoIdGenerator>((ref) {
  return SequentialCustomerPhotoIdGenerator();
});

// Phase 6M — unified Audit Center projection. See
// `BuildAuditCenterProjection`'s own doc comment for exactly which 4 of
// this codebase's 8 audit trails are included and why.
final buildAuditCenterProjectionProvider =
    Provider<BuildAuditCenterProjection>((ref) {
  return BuildAuditCenterProjection(
    courierAuditRepository:
        ref.watch(courierOperationalAuditEntryRepositoryProvider),
    kitchenAuditRepository: ref.watch(kitchenAuditEntryRepositoryProvider),
    restaurantOperationsAuditRepository:
        ref.watch(restaurantOperationsAuditEntryRepositoryProvider),
    adminAuditRepository: ref.watch(adminAuditEntryRepositoryProvider),
  );
});

// Phase 6L — device & integration registry foundation.
final adminDeviceRegistrationRepositoryProvider =
    Provider<AdminDeviceRegistrationRepository>((ref) {
  return InMemoryAdminDeviceRegistrationRepository();
});

final adminDeviceRegistrationIdGeneratorProvider =
    Provider<AdminDeviceRegistrationIdGenerator>((ref) {
  return SequentialAdminDeviceRegistrationIdGenerator();
});

final buildDeviceRegistryProjectionProvider =
    Provider<BuildDeviceRegistryProjection>((ref) {
  return BuildDeviceRegistryProjection(
    kitchenDisplayDeviceRepository:
        ref.watch(kitchenDisplayDeviceRepositoryProvider),
    courierRepository: ref.watch(courierRepositoryProvider),
    courierDeviceRepository: ref.watch(courierDeviceRepositoryProvider),
    adminDeviceRegistrationRepository:
        ref.watch(adminDeviceRegistrationRepositoryProvider),
  );
});

// Phase 6N — localization administration foundation.
final localizationConfigRepositoryProvider =
    Provider<LocalizationConfigRepository>((ref) {
  return InMemoryLocalizationConfigRepository();
});

final localizationConfigIdGeneratorProvider =
    Provider<LocalizationConfigIdGenerator>((ref) {
  return SequentialLocalizationConfigIdGenerator();
});

final translationEntryRepositoryProvider =
    Provider<TranslationEntryRepository>((ref) {
  return InMemoryTranslationEntryRepository();
});

final translationEntryIdGeneratorProvider =
    Provider<TranslationEntryIdGenerator>((ref) {
  return SequentialTranslationEntryIdGenerator();
});

// Phase 6O — feature flags/settings/system health foundation.
final maintenanceModeStateRepositoryProvider =
    Provider<MaintenanceModeStateRepository>((ref) {
  return InMemoryMaintenanceModeStateRepository();
});
