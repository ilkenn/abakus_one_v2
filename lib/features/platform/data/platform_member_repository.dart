import '../domain/member/platform_member.dart';

/// Mutable registry storage for [PlatformMember] — mirrors
/// `StaffMemberRepository`.
abstract interface class PlatformMemberRepository {
  Future<void> save(PlatformMember member);

  /// [remintToken] (2026-10-30) — only ever supplied, and only ever
  /// meaningful, for `FirebasePlatformMemberRepository`'s Windows-REST
  /// path (see that class's own `findById` doc comment); every other
  /// implementation ignores it.
  Future<PlatformMember?> findById(
    String platformMemberId, {
    Future<void> Function()? remintToken,
  });
  Future<List<PlatformMember>> findAll();

  /// The credential-linkage lookup key — Sprint 9C
  /// (`docs/decisions.md` ADR-026). Mirrors
  /// `StaffMemberRepository.findByAuthUid` exactly.
  Future<PlatformMember?> findByAuthUid(
    String authUid, {
    Future<void> Function()? remintToken,
  });
}

/// Selected in release builds — Phase 8 closure sprint
/// (`docs/decisions.md` ADR-025). Mirrors
/// `ProductionUnavailableStaffMemberRepository`'s exact reasoning one
/// tier up: "the roster itself must never be available in Release,"
/// enforced structurally rather than by `PlatformSignInScreen`'s own
/// discipline. Selected via `platformMemberRepositoryProvider`'s
/// `kReleaseMode` switch (`platform_dependencies_provider.dart`).
class ProductionUnavailablePlatformMemberRepository
    implements PlatformMemberRepository {
  const ProductionUnavailablePlatformMemberRepository();

  @override
  Future<void> save(PlatformMember member) async {
    throw StateError(
      'PlatformMemberRepository is unavailable in release builds — no '
      'real backend exists yet.',
    );
  }

  @override
  Future<PlatformMember?> findById(
    String platformMemberId, {
    Future<void> Function()? remintToken,
  }) async =>
      null;

  @override
  Future<List<PlatformMember>> findAll() async => const [];

  @override
  Future<PlatformMember?> findByAuthUid(
    String authUid, {
    Future<void> Function()? remintToken,
  }) async =>
      null;
}

class InMemoryPlatformMemberRepository implements PlatformMemberRepository {
  final Map<String, PlatformMember> _byId = {};

  @override
  Future<void> save(PlatformMember member) async => _byId[member.id] = member;

  @override
  Future<PlatformMember?> findById(
    String platformMemberId, {
    Future<void> Function()? remintToken,
  }) async =>
      _byId[platformMemberId];

  @override
  Future<List<PlatformMember>> findAll() async =>
      List.unmodifiable(_byId.values);

  @override
  Future<PlatformMember?> findByAuthUid(
    String authUid, {
    Future<void> Function()? remintToken,
  }) async {
    for (final member in _byId.values) {
      if (member.authUid == authUid) return member;
    }
    return null;
  }
}
