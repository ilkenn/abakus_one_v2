import '../domain/member/platform_member.dart';

/// Mutable registry storage for [PlatformMember] — mirrors
/// `StaffMemberRepository`.
abstract interface class PlatformMemberRepository {
  Future<void> save(PlatformMember member);
  Future<PlatformMember?> findById(String platformMemberId);
  Future<List<PlatformMember>> findAll();
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
