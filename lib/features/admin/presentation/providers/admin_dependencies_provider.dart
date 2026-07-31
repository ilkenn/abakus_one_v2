import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/identity/staff_member_id_generator.dart';
import '../../application/identity/staff_role_change_event_id_generator.dart';
import '../../data/admin_audit_entry_repository.dart';
import '../../data/staff_auth_repository.dart';
import '../../data/staff_member_repository.dart';
import '../../data/staff_role_change_event_repository.dart';

/// Central Riverpod wiring for `features/admin` — mirrors
/// `crm_dependencies_provider.dart`'s shape (Phase 6, `docs/decisions.md`
/// ADR-023).
final staffMemberRepositoryProvider = Provider<StaffMemberRepository>((ref) {
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
