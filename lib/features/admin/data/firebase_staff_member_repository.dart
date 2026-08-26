import 'package:cloud_functions/cloud_functions.dart' as functions;

import '../../pos/domain/authorization/staff_role.dart';
import '../domain/staff/staff_member.dart';
import '../domain/staff/staff_member_status.dart';
import 'staff_member_repository.dart';

/// Mirrors `AdminReservationException`'s exact shape
/// (`admin_reservation_gateway.dart`) — deliberately duplicated, not
/// imported, matching that file's own established precedent for
/// staff-facing gateway errors staying feature-local.
class StaffDirectoryException implements Exception {
  const StaffDirectoryException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'StaffDirectoryException($code): $message';
}

/// AP-2 Stage B — the real, Firebase-backed [StaffMemberRepository].
/// Read side calls `listStaffMembersForOrganization` (the new read-model
/// callable this phase added, closing the gap that `firestore.rules`'
/// `memberships` rule restricts a client to reading only their own
/// document). [save] diffs the passed [StaffMember] against the last
/// state this instance observed for that id (populated by [findAll]/
/// [findById]/[findByBranch]) and dispatches exactly the specific
/// mutation callable(s) needed (`assignStaffRole`/`revokeStaffRole`/
/// `grantStaffBranchAccess`/`revokeStaffBranchAccess`/
/// `setStaffMemberStatus`) — every existing use case
/// (`AssignStaffRole`/`RevokeStaffRole`/etc.) keeps calling `save()`
/// unchanged; this repository is the one place that translates "the
/// whole new object" into "the one real command that actually changed."
/// The backend independently re-verifies authorization for every one of
/// these commands regardless of what this client-side diff computes —
/// this repository's own diff is a dispatch mechanism, never itself the
/// authorization boundary.
///
/// **A known, disclosed limitation**: the real `memberships` collection
/// this repository is backed by carries no display-name field at all
/// (`functions/src/staffMembership.ts`'s own doc comment: "Persists only
/// memberships/{organizationId}_{uid}... not the fuller `staffMembers`
/// admin-display record"). Building that admin-display collection remains
/// explicitly deferred, separate scope (an earlier-phase decision, unchanged
/// by AP-2). Until then, [StaffMember.displayName] here is the linked
/// Firebase Auth `uid` itself — a disclosed placeholder, never a
/// fabricated name — except for a just-[register]ed member within the
/// same session, where the real name entered at registration time is used.
class FirebaseStaffMemberRepository implements StaffMemberRepository {
  FirebaseStaffMemberRepository({required String Function() organizationId})
      : _organizationId = organizationId;

  final String Function() _organizationId;
  final Map<String, StaffMember> _cache = {};

  functions.HttpsCallable _callable(String name) =>
      functions.FirebaseFunctions.instance.httpsCallable(name);

  Never _rethrow(functions.FirebaseFunctionsException error) {
    throw StaffDirectoryException(
      error.code,
      error.message ?? 'Beklenmeyen bir hata oluştu.',
    );
  }

  StaffRole? _roleFromName(String name) {
    for (final role in StaffRole.values) {
      if (role.name == name) return role;
    }
    return null;
  }

  StaffMemberStatus _statusFromName(String name) {
    for (final status in StaffMemberStatus.values) {
      if (status.name == name) return status;
    }
    return StaffMemberStatus.active;
  }

  StaffMember _mapEntry(Map<String, dynamic> raw) {
    final uid = raw['uid'] as String;
    final roles = <StaffRole>{
      for (final r in (raw['roles'] as List))
        if (_roleFromName(r as String) case final role?) role,
    };
    final member = StaffMember(
      id: uid,
      displayName: _cache[uid]?.displayName ?? uid,
      authUid: uid,
      roles: roles,
      branchAccess: Set<String>.from(raw['branchAccess'] as List),
      organizationAccess: {_organizationId()},
      status: _statusFromName(raw['status'] as String),
      createdAt: _cache[uid]?.createdAt ?? DateTime.now(),
      revision: (_cache[uid]?.revision ?? 0) + 1,
    );
    _cache[uid] = member;
    return member;
  }

  @override
  Future<List<StaffMember>> findAll() async {
    try {
      final result = await _callable('listStaffMembersForOrganization')
          .call<Map<String, dynamic>>({'organizationId': _organizationId()});
      final rawMembers = result.data['members'] as List;
      return [
        for (final raw in rawMembers)
          _mapEntry(Map<String, dynamic>.from(raw as Map)),
      ];
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<List<StaffMember>> findByBranch(String branchId) async {
    final all = await findAll();
    return all.where((m) => m.branchAccess.contains(branchId)).toList();
  }

  @override
  Future<StaffMember?> findById(String staffMemberId) async {
    final all = await findAll();
    for (final member in all) {
      if (member.id == staffMemberId) return member;
    }
    return null;
  }

  @override
  Future<StaffMember?> findByAuthUid(String authUid) => findById(authUid);

  @override
  Future<StaffMember> register({
    required String displayName,
    required String email,
  }) async {
    try {
      final result =
          await _callable('registerStaffMember').call<Map<String, dynamic>>({
        'organizationId': _organizationId(),
        'email': email,
      });
      final uid = result.data['uid'] as String;
      final member = StaffMember(
        id: uid,
        displayName: displayName,
        authUid: uid,
        organizationAccess: {_organizationId()},
        createdAt: DateTime.now(),
        revision: 1,
      );
      _cache[uid] = member;
      return member;
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<void> save(StaffMember member) async {
    final previous = _cache[member.id];
    if (previous == null) {
      // No prior known state to diff against in this repository instance
      // (e.g. save() called without a preceding findById/findAll/register
      // for this id) — conservatively refuses rather than silently
      // guessing at which command to dispatch.
      throw StateError(
        'FirebaseStaffMemberRepository.save() requires a prior findById(), '
        'findAll(), or register() call for this member in the same '
        'session — there is nothing to diff against.',
      );
    }

    final organizationId = _organizationId();

    for (final role in member.roles.difference(previous.roles)) {
      await _dispatch('assignStaffRole', {
        'organizationId': organizationId,
        'targetUid': member.id,
        'role': role.name,
      });
    }
    for (final role in previous.roles.difference(member.roles)) {
      await _dispatch('revokeStaffRole', {
        'organizationId': organizationId,
        'targetUid': member.id,
        'role': role.name,
      });
    }

    for (final branchId
        in member.branchAccess.difference(previous.branchAccess)) {
      await _dispatch('grantStaffBranchAccess', {
        'organizationId': organizationId,
        'targetUid': member.id,
        'branchId': branchId,
      });
    }
    for (final branchId
        in previous.branchAccess.difference(member.branchAccess)) {
      await _dispatch('revokeStaffBranchAccess', {
        'organizationId': organizationId,
        'targetUid': member.id,
        'branchId': branchId,
      });
    }

    if (member.status != previous.status) {
      await _dispatch('setStaffMemberStatus', {
        'organizationId': organizationId,
        'targetUid': member.id,
        'status': member.status.name,
      });
    }

    _cache[member.id] = member;
  }

  Future<void> _dispatch(String name, Map<String, dynamic> data) async {
    try {
      await _callable(name).call<Map<String, dynamic>>(data);
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }
}
