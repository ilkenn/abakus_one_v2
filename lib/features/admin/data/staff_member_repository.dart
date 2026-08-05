import '../domain/staff/staff_member.dart';

/// Mutable registry storage for [StaffMember] — mirrors `CourierRepository`.
abstract interface class StaffMemberRepository {
  Future<void> save(StaffMember member);
  Future<StaffMember?> findById(String staffMemberId);
  Future<List<StaffMember>> findAll();
  Future<List<StaffMember>> findByBranch(String branchId);
}

/// Selected in release builds — Phase 8 closure sprint
/// (`docs/decisions.md` ADR-025). "The roster itself must never be
/// available in Release": exposes zero member metadata (no names,
/// roles, or statuses) regardless of caller, structurally rather than
/// by `StaffSignInScreen`'s own discipline — mirrors
/// `ProductionUnavailableStaffAuthRepository`'s exact "fails closed"
/// reasoning, applied to enumeration instead of sign-in. Selected via
/// `staffMemberRepositoryProvider`'s `kReleaseMode` switch
/// (`admin_dependencies_provider.dart`).
class ProductionUnavailableStaffMemberRepository
    implements StaffMemberRepository {
  const ProductionUnavailableStaffMemberRepository();

  @override
  Future<void> save(StaffMember member) async {
    throw StateError(
      'StaffMemberRepository is unavailable in release builds — no real '
      'backend exists yet.',
    );
  }

  @override
  Future<StaffMember?> findById(String staffMemberId) async => null;

  @override
  Future<List<StaffMember>> findAll() async => const [];

  @override
  Future<List<StaffMember>> findByBranch(String branchId) async => const [];
}

class InMemoryStaffMemberRepository implements StaffMemberRepository {
  final Map<String, StaffMember> _byId = {};

  @override
  Future<void> save(StaffMember member) async => _byId[member.id] = member;

  @override
  Future<StaffMember?> findById(String staffMemberId) async =>
      _byId[staffMemberId];

  @override
  Future<List<StaffMember>> findAll() async => List.unmodifiable(_byId.values);

  @override
  Future<List<StaffMember>> findByBranch(String branchId) async {
    return List.unmodifiable(
      _byId.values.where((m) => m.branchAccess.contains(branchId)),
    );
  }
}
