import '../domain/staff/staff_member.dart';

/// Mutable registry storage for [StaffMember] — mirrors `CourierRepository`.
abstract interface class StaffMemberRepository {
  Future<void> save(StaffMember member);
  Future<StaffMember?> findById(String staffMemberId);
  Future<List<StaffMember>> findAll();
  Future<List<StaffMember>> findByBranch(String branchId);

  /// The credential-linkage lookup key — Sprint 9C
  /// (`docs/decisions.md` ADR-026). `null` when no member is linked to
  /// this Firebase Auth UID — `FirebaseStaffAuthRepository` treats that
  /// exactly like "member not found," never falling back to any other
  /// lookup.
  Future<StaffMember?> findByAuthUid(String authUid);

  /// AP-2 Stage B — a dedicated create-with-credential-linkage operation,
  /// separate from [save] (which only ever mutates an EXISTING record for
  /// every real implementation of this interface — see
  /// `FirebaseStaffMemberRepository`'s own doc comment for why creation
  /// specifically needs [email]: the real backend links a new membership
  /// to an *existing* Firebase Auth account found by email, something
  /// [StaffMember] itself has no field for and [save] alone cannot express).
  Future<StaffMember> register({
    required String displayName,
    required String email,
  });
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

  @override
  Future<StaffMember?> findByAuthUid(String authUid) async => null;

  @override
  Future<StaffMember> register({
    required String displayName,
    required String email,
  }) async {
    throw StateError(
      'StaffMemberRepository is unavailable in release builds — no real '
      'backend exists yet.',
    );
  }
}

class InMemoryStaffMemberRepository implements StaffMemberRepository {
  int _sequence = 0;
  final Map<String, StaffMember> _byId = {};

  @override
  Future<void> save(StaffMember member) async => _byId[member.id] = member;

  @override
  Future<StaffMember> register({
    required String displayName,
    required String email,
  }) async {
    final member = StaffMember(
      id: 'staff-member-${++_sequence}',
      displayName: displayName,
      createdAt: DateTime.now(),
      revision: 1,
    );
    _byId[member.id] = member;
    return member;
  }

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

  @override
  Future<StaffMember?> findByAuthUid(String authUid) async {
    for (final member in _byId.values) {
      if (member.authUid == authUid) return member;
    }
    return null;
  }
}
