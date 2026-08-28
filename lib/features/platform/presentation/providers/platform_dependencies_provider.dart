import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../bootstrap/firebase_ready_provider.dart';
import '../../../../core/services/auth/email_password_auth_client.dart';
import '../../../../core/services/auth/platform_claims_sync_client.dart';
import '../../../admin/data/organization_repository.dart';
import '../../application/identity/platform_member_id_generator.dart';
import '../../data/entitlement_admin_gateway.dart';
import '../../data/firebase_platform_member_repository.dart';
import '../../data/firestore_platform_organization_repository.dart';
import '../../data/platform_audit_entry_repository.dart';
import '../../data/platform_auth_repository.dart';
import '../../data/platform_customer_directory_gateway.dart';
import '../../data/platform_member_repository.dart';

final platformClaimsSyncClientProvider =
    Provider<PlatformClaimsSyncClient>((ref) {
  return DefaultPlatformClaimsSyncClient();
});

/// Central Riverpod wiring for `features/platform` — Phase 8
/// (`docs/decisions.md` ADR-025). Mirrors
/// `admin_dependencies_provider.dart`'s shape for the wholly separate
/// platform-owner hierarchy.
///
/// AP-2 final wiring — [firebaseReadyProvider] now selects the real,
/// `platformMembers`-collection-backed [FirebasePlatformMemberRepository]
/// (mirrors `staffMemberRepositoryProvider`'s own exact gate shape one
/// tier up), closing the real gap the AP-2 audit found:
/// `FirebasePlatformAuthRepository.signIn` already called
/// `findByAuthUid` against a real Firebase Auth result, but no real
/// repository implementation existed to answer it — sign-in could never
/// actually succeed. `kReleaseMode` remains the fallback gate when
/// Firebase isn't ready — Phase 8 closure sprint's (`docs/decisions.md`
/// ADR-025) "the roster itself must never be available in Release" still
/// holds: a release build with no healthy Firebase connection gets
/// [ProductionUnavailablePlatformMemberRepository], never the in-memory
/// stand-in.
final platformMemberRepositoryProvider =
    Provider<PlatformMemberRepository>((ref) {
  final isFirebaseReady = ref.watch(firebaseReadyProvider);
  if (isFirebaseReady) {
    return FirebasePlatformMemberRepository(
      claimsSyncClient: ref.watch(platformClaimsSyncClientProvider),
    );
  }
  if (kReleaseMode) {
    return const ProductionUnavailablePlatformMemberRepository();
  }
  return InMemoryPlatformMemberRepository();
});

final platformMemberIdGeneratorProvider =
    Provider<PlatformMemberIdGenerator>((ref) {
  return SequentialPlatformMemberIdGenerator();
});

final platformAuditEntryRepositoryProvider =
    Provider<PlatformAuditEntryRepository>((ref) {
  return InMemoryPlatformAuditEntryRepository();
});

/// AP-2 final wiring — the tenant picker's real data source. Falls back
/// to an explicit "unavailable" implementation (fails closed, never a
/// silently-empty tenant list) when Firebase isn't ready.
final platformOrganizationRepositoryProvider =
    Provider<OrganizationRepository>((ref) {
  final isFirebaseReady = ref.watch(firebaseReadyProvider);
  if (isFirebaseReady) {
    return FirestorePlatformOrganizationRepository();
  }
  return const UnavailablePlatformOrganizationRepository();
});

final entitlementAdminGatewayProvider =
    Provider<EntitlementAdminGateway>((ref) {
  final isFirebaseReady = ref.watch(firebaseReadyProvider);
  if (isFirebaseReady) {
    return const FirebaseEntitlementAdminGateway();
  }
  return const UnavailableEntitlementAdminGateway();
});

/// AP-3 continuation — the Platform Owner's real global Customer Directory
/// backend. Same gate shape as [entitlementAdminGatewayProvider].
final platformCustomerDirectoryGatewayProvider =
    Provider<PlatformCustomerDirectoryGateway>((ref) {
  final isFirebaseReady = ref.watch(firebaseReadyProvider);
  if (isFirebaseReady) {
    return const FirebasePlatformCustomerDirectoryGateway();
  }
  return const UnavailablePlatformCustomerDirectoryGateway();
});

/// [firebaseReadyProvider] selects the fail-closed implementation —
/// Sprint 9C (`docs/decisions.md` ADR-026), superseding the previous
/// `kReleaseMode` split, exactly mirroring `staffAuthRepositoryProvider`'s
/// own gate.
final platformAuthRepositoryProvider = Provider<PlatformAuthRepository>((ref) {
  final isFirebaseReady = ref.watch(firebaseReadyProvider);
  if (!isFirebaseReady) {
    return const ProductionUnavailablePlatformAuthRepository();
  }
  return FirebasePlatformAuthRepository(
    authClient: DefaultEmailPasswordAuthClient(),
    platformMemberRepository: ref.watch(platformMemberRepositoryProvider),
    sessionDuration: () => const Duration(hours: 12),
  );
});
