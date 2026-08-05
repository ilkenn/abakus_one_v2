import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
/// `kReleaseMode`-gated — Phase 8 closure sprint (`docs/decisions.md`
/// ADR-025): "the roster itself must never be available in Release."
/// Every reachable consumer of this provider (`StaffSignInScreen`'s
/// enumeration, `StaffManagementScreen`/`StaffDetailScreen`) already
/// requires a real `ActorSession`, which `staffAuthRepositoryProvider`'s
/// own `kReleaseMode` gate makes impossible to obtain in a release
/// build — this mirrors that same gate at the data layer instead of
/// relying solely on "nothing can reach it," the same "never trust the
/// caller" reasoning Phase 8's read-projection self-authorization uses.
final staffMemberRepositoryProvider = Provider<StaffMemberRepository>((ref) {
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

/// `kReleaseMode` selects the fail-closed implementation — exactly
/// mirroring `authRepositoryProvider`'s own release/debug split
/// (`features/auth`). "Do not claim production backend validation if
/// none exists."
final staffAuthRepositoryProvider = Provider<StaffAuthRepository>((ref) {
  if (kReleaseMode) {
    return const ProductionUnavailableStaffAuthRepository();
  }
  return DevelopmentStaffAuthRepository(
    staffMemberRepository: ref.watch(staffMemberRepositoryProvider),
    sessionDuration: () => const Duration(hours: 12),
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
/// (`docs/decisions.md` ADR-025). **A placeholder, not real tenant
/// selection**: this app has no tenant-switching UI anywhere yet (no
/// screen lets an actor pick which organization's build they're
/// running), so this always resolves to the single seeded organization
/// above — mirrors `currentBranchIdProvider`'s exact honest-placeholder
/// pattern (`features/navigation`) for the same reason. Building real
/// tenant selection/provisioning is separate, unrelated feature work.
final currentOrganizationIdProvider = Provider<String>((ref) => 'org-1');

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
