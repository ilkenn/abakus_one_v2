import '../domain/member/platform_member.dart';

/// Mutable registry storage for [PlatformMember] — mirrors
/// `StaffMemberRepository`.
abstract interface class PlatformMemberRepository {
  Future<void> save(PlatformMember member);
  Future<PlatformMember?> findById(String platformMemberId);
  Future<List<PlatformMember>> findAll();
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
  Future<PlatformMember?> findById(String platformMemberId) async => null;

  @override
  Future<List<PlatformMember>> findAll() async => const [];
}

class InMemoryPlatformMemberRepository implements PlatformMemberRepository {
  final Map<String, PlatformMember> _byId = {};

  @override
  Future<void> save(PlatformMember member) async => _byId[member.id] = member;

  @override
  Future<PlatformMember?> findById(String platformMemberId) async =>
      _byId[platformMemberId];

  @override
  Future<List<PlatformMember>> findAll() async =>
      List.unmodifiable(_byId.values);
}
