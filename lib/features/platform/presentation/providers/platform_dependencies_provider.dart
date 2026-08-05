import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/identity/platform_member_id_generator.dart';
import '../../data/platform_audit_entry_repository.dart';
import '../../data/platform_auth_repository.dart';
import '../../data/platform_member_repository.dart';

/// Central Riverpod wiring for `features/platform` — Phase 8
/// (`docs/decisions.md` ADR-025). Mirrors
/// `admin_dependencies_provider.dart`'s shape for the wholly separate
/// platform-owner hierarchy.
/// `kReleaseMode`-gated — Phase 8 closure sprint (`docs/decisions.md`
/// ADR-025): "the roster itself must never be available in Release."
/// Mirrors `staffMemberRepositoryProvider`'s identical gate one tier up
/// — every reachable consumer already requires a real
/// `PlatformActorSession`, impossible in release since
/// `platformAuthRepositoryProvider` fails closed there too, but this
/// gate holds at the data layer regardless, never relying solely on
/// "nothing can reach it."
final platformMemberRepositoryProvider =
    Provider<PlatformMemberRepository>((ref) {
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

/// `kReleaseMode` selects the fail-closed implementation — exactly
/// mirroring `staffAuthRepositoryProvider`'s own release/debug split.
/// "Release builds must never expose this path" (Phase 8 kickoff).
final platformAuthRepositoryProvider = Provider<PlatformAuthRepository>((ref) {
  if (kReleaseMode) {
    return const ProductionUnavailablePlatformAuthRepository();
  }
  return DevelopmentPlatformAuthRepository(
    platformMemberRepository: ref.watch(platformMemberRepositoryProvider),
    sessionDuration: () => const Duration(hours: 12),
  );
});
