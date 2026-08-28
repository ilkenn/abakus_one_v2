import 'package:abakus_one_v2/core/services/auth/staff_claims_sync_client.dart';
import 'package:abakus_one_v2/features/admin/data/staff_auth_repository.dart';
import 'package:abakus_one_v2/features/admin/data/staff_member_repository.dart';
import 'package:abakus_one_v2/features/admin/domain/staff/staff_member.dart';
import 'package:abakus_one_v2/features/admin/domain/staff/staff_member_status.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/actor_session.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/staff_role.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/services/auth/fake_email_password_auth_client.dart';
import '../../../core/services/auth/fake_staff_claims_sync_client.dart';
import '../test_support/admin_test_fixtures.dart';

const _testOrgId = 'org-1';

void main() {
  group(
      'FirebaseStaffAuthRepository.signIn — claims are the authority '
      '(Faz R.3A.2)', () {
    test(
        'succeeds when the credential is valid and refreshed claims carry '
        'a manager role for the org, even with no linked StaffMember at all',
        () async {
      final authClient = FakeEmailPasswordAuthClient();
      final created = await authClient.createAccount(
          email: 'manager@abakus.test', password: 'S3curePass!');
      final repository = FirebaseStaffAuthRepository(
        authClient: authClient,
        staffMemberRepository: InMemoryStaffMemberRepository(),
        sessionDuration: () => const Duration(hours: 1),
        claimsSyncClient: FakeStaffClaimsSyncClient(
          claimsToReturn: const StaffAuthorizationClaims(
            organizationAccess: [_testOrgId],
            rolesByOrganization: {
              _testOrgId: ['manager'],
            },
            branchAccessByOrganization: {},
          ),
        ),
        organizationId: () => _testOrgId,
      );

      final session = await repository.signIn(
          email: 'manager@abakus.test', password: 'S3curePass!');

      expect(session, isNotNull);
      expect(session!.roles, {StaffRole.manager});
      expect(session.actorId, created.uid); // falls back to the Firebase uid
      expect(session.organizationAccess, {_testOrgId});
    });

    test('succeeds with tenantOwner claims', () async {
      final authClient = FakeEmailPasswordAuthClient();
      await authClient.createAccount(
          email: 'owner@abakus.test', password: 'S3curePass!');
      final repository = FirebaseStaffAuthRepository(
        authClient: authClient,
        staffMemberRepository: InMemoryStaffMemberRepository(),
        sessionDuration: () => const Duration(hours: 1),
        claimsSyncClient: FakeStaffClaimsSyncClient(
          claimsToReturn: const StaffAuthorizationClaims(
            organizationAccess: [_testOrgId],
            rolesByOrganization: {
              _testOrgId: ['tenantOwner'],
            },
            branchAccessByOrganization: {},
          ),
        ),
        organizationId: () => _testOrgId,
      );

      final session = await repository.signIn(
          email: 'owner@abakus.test', password: 'S3curePass!');

      expect(session, isNotNull);
      expect(session!.roles, {StaffRole.tenantOwner});
    });

    test(
        'a linked, active StaffMember only ever supplies profile metadata '
        '(id) — never the roles OR the branch access the session carries '
        '(Faz R.3C.2: branchAccess is now claims-sourced too)', () async {
      final authClient = FakeEmailPasswordAuthClient();
      final created = await authClient.createAccount(
          email: 'manager@abakus.test', password: 'S3curePass!');
      final memberRepository = InMemoryStaffMemberRepository();
      await memberRepository.save(buildTestStaffMember(
        id: 'staff-1',
        // StaffMember itself claims 'staff' + branch-1 — both the role AND
        // the branch must be ignored; only the claims' own values should
        // ever surface in the resulting session.
        roles: {StaffRole.staff},
        branchAccess: {'branch-1'},
        authUid: created.uid,
      ));
      final repository = FirebaseStaffAuthRepository(
        authClient: authClient,
        staffMemberRepository: memberRepository,
        sessionDuration: () => const Duration(hours: 1),
        claimsSyncClient: FakeStaffClaimsSyncClient(
          claimsToReturn: const StaffAuthorizationClaims(
            organizationAccess: [_testOrgId],
            rolesByOrganization: {
              _testOrgId: ['manager'],
            },
            branchAccessByOrganization: {
              _testOrgId: ['branch-2'],
            },
          ),
        ),
        organizationId: () => _testOrgId,
      );

      final session = await repository.signIn(
          email: 'manager@abakus.test', password: 'S3curePass!');

      expect(session, isNotNull);
      expect(
          session!.actorId, 'staff-1'); // profile metadata, used when present
      expect(session.roles,
          {StaffRole.manager}); // from claims, not StaffMember.roles
      expect(session.branchAccess, {'branch-2'},
          reason: 'branch access must come from the claim, never from '
              'StaffMember.branchAccess — the two deliberately disagree '
              'here (branch-1 vs branch-2) to prove which one wins');
    });

    test(
        'StaffMemberRepository.branchAccess grants no branch authorization '
        'at all — an empty claim means empty session access even when '
        'StaffMember claims broad branch access (Faz R.3C.2)', () async {
      final authClient = FakeEmailPasswordAuthClient();
      final created = await authClient.createAccount(
          email: 'manager2@abakus.test', password: 'S3curePass!');
      final memberRepository = InMemoryStaffMemberRepository();
      await memberRepository.save(buildTestStaffMember(
        id: 'staff-2',
        roles: {StaffRole.manager},
        branchAccess: {'branch-1', 'branch-2', 'branch-3'},
        authUid: created.uid,
      ));
      final repository = FirebaseStaffAuthRepository(
        authClient: authClient,
        staffMemberRepository: memberRepository,
        sessionDuration: () => const Duration(hours: 1),
        claimsSyncClient: FakeStaffClaimsSyncClient(
          claimsToReturn: const StaffAuthorizationClaims(
            organizationAccess: [_testOrgId],
            rolesByOrganization: {
              _testOrgId: ['manager'],
            },
            branchAccessByOrganization: {}, // no branchAccess entry at all
          ),
        ),
        organizationId: () => _testOrgId,
      );

      final session = await repository.signIn(
          email: 'manager2@abakus.test', password: 'S3curePass!');

      expect(session, isNotNull);
      expect(session!.branchAccess, isEmpty,
          reason: 'StaffMember.branchAccess must never grant branch '
              'authorization the real claims did not — it is display '
              'metadata only from this phase on');
    });

    test(
        'denies when refreshed claims carry no role for the org, even if '
        'a linked StaffMember shows active with roles (claims are '
        'authoritative over StaffMember, not the other way around)', () async {
      final authClient = FakeEmailPasswordAuthClient();
      final created = await authClient.createAccount(
          email: 'stale@abakus.test', password: 'S3curePass!');
      final memberRepository = InMemoryStaffMemberRepository();
      await memberRepository.save(buildTestStaffMember(
        id: 'staff-1',
        roles: {StaffRole.admin},
        status: StaffMemberStatus.active,
        authUid: created.uid,
      ));
      final repository = FirebaseStaffAuthRepository(
        authClient: authClient,
        staffMemberRepository: memberRepository,
        sessionDuration: () => const Duration(hours: 1),
        claimsSyncClient:
            FakeStaffClaimsSyncClient(), // defaults to empty claims
        organizationId: () => _testOrgId,
      );

      final session = await repository.signIn(
          email: 'stale@abakus.test', password: 'S3curePass!');

      expect(session, isNull);
    });

    test('denies an invalid credential outright (no claims call needed)',
        () async {
      final authClient = FakeEmailPasswordAuthClient();
      final claimsSyncClient = FakeStaffClaimsSyncClient();
      final repository = FirebaseStaffAuthRepository(
        authClient: authClient,
        staffMemberRepository: InMemoryStaffMemberRepository(),
        sessionDuration: () => const Duration(hours: 1),
        claimsSyncClient: claimsSyncClient,
        organizationId: () => _testOrgId,
      );

      final session = await repository.signIn(
          email: 'nobody@abakus.test', password: 'wrong');

      expect(session, isNull);
      expect(claimsSyncClient.callCount, 0);
    });

    test(
        'denies when claims-sync reports no Firebase user actually signed '
        'in (defensive — should not happen right after a successful auth '
        'sign-in, but must fail closed if it ever does)', () async {
      final authClient = FakeEmailPasswordAuthClient();
      await authClient.createAccount(
          email: 'manager@abakus.test', password: 'S3curePass!');
      final repository = FirebaseStaffAuthRepository(
        authClient: authClient,
        staffMemberRepository: InMemoryStaffMemberRepository(),
        sessionDuration: () => const Duration(hours: 1),
        claimsSyncClient: FakeStaffClaimsSyncClient(claimsToReturn: null),
        organizationId: () => _testOrgId,
      );

      final session = await repository.signIn(
          email: 'manager@abakus.test', password: 'S3curePass!');

      expect(session, isNull);
    });

    test(
        'no ProductionUnavailableStaffMemberRepository dependency remains '
        'on the authorization-critical path — a release-mode staff member '
        'with real refreshed claims still gets a valid session', () async {
      final authClient = FakeEmailPasswordAuthClient();
      await authClient.createAccount(
          email: 'manager@abakus.test', password: 'S3curePass!');
      final repository = FirebaseStaffAuthRepository(
        authClient: authClient,
        // The exact implementation `staffMemberRepositoryProvider` selects
        // in release builds — always returns null from every lookup.
        staffMemberRepository:
            const ProductionUnavailableStaffMemberRepository(),
        sessionDuration: () => const Duration(hours: 1),
        claimsSyncClient: FakeStaffClaimsSyncClient(
          claimsToReturn: const StaffAuthorizationClaims(
            organizationAccess: [_testOrgId],
            rolesByOrganization: {
              _testOrgId: ['manager'],
            },
            branchAccessByOrganization: {},
          ),
        ),
        organizationId: () => _testOrgId,
      );

      final session = await repository.signIn(
          email: 'manager@abakus.test', password: 'S3curePass!');

      expect(session, isNotNull);
      expect(session!.roles, {StaffRole.manager});
    });

    test(
        'a StaffMemberRepository lookup that throws (e.g. a slow/unavailable '
        'directory query) never denies or hangs sign-in — profile metadata '
        'is best-effort only, exactly as this class documents itself',
        () async {
      final authClient = FakeEmailPasswordAuthClient();
      await authClient.createAccount(
          email: 'manager@abakus.test', password: 'S3curePass!');
      final repository = FirebaseStaffAuthRepository(
        authClient: authClient,
        staffMemberRepository: _ThrowingStaffMemberRepository(),
        sessionDuration: () => const Duration(hours: 1),
        claimsSyncClient: FakeStaffClaimsSyncClient(
          claimsToReturn: const StaffAuthorizationClaims(
            organizationAccess: [_testOrgId],
            rolesByOrganization: {
              _testOrgId: ['manager'],
            },
            branchAccessByOrganization: {},
          ),
        ),
        organizationId: () => _testOrgId,
      );

      final session = await repository.signIn(
          email: 'manager@abakus.test', password: 'S3curePass!');

      expect(session, isNotNull);
      expect(session!.roles, {StaffRole.manager});
    });
  });

  group(
      'FirebaseStaffAuthRepository.refreshSession — claims are '
      're-derived, not re-read from StaffMember alone (Faz R.3A.2)', () {
    test(
        'a role granted after the original sign-in is reflected once '
        'refreshSession re-syncs and re-parses claims', () async {
      final claimsSyncClient = FakeStaffClaimsSyncClient(
        claimsToReturn: const StaffAuthorizationClaims(
          organizationAccess: [_testOrgId],
          rolesByOrganization: {
            _testOrgId: ['manager', 'admin'],
          },
          branchAccessByOrganization: {},
        ),
      );
      final repository = FirebaseStaffAuthRepository(
        authClient: FakeEmailPasswordAuthClient(),
        staffMemberRepository: InMemoryStaffMemberRepository(),
        sessionDuration: () => const Duration(hours: 1),
        claimsSyncClient: claimsSyncClient,
        organizationId: () => _testOrgId,
      );
      const current = ActorSession(
        actorId: 'uid-1',
        roles: {StaffRole.manager},
        activeRole: StaffRole.manager,
      );

      final refreshed = await repository.refreshSession(current);

      expect(refreshed, isNotNull);
      expect(refreshed!.roles, {StaffRole.manager, StaffRole.admin});
    });

    test(
        'a branch granted after the original sign-in is reflected once '
        'refreshSession re-syncs and re-parses claims (Faz R.3C.2)', () async {
      final claimsSyncClient = FakeStaffClaimsSyncClient(
        claimsToReturn: const StaffAuthorizationClaims(
          organizationAccess: [_testOrgId],
          rolesByOrganization: {
            _testOrgId: ['manager'],
          },
          branchAccessByOrganization: {
            _testOrgId: ['branch-1', 'branch-2'],
          },
        ),
      );
      final repository = FirebaseStaffAuthRepository(
        authClient: FakeEmailPasswordAuthClient(),
        staffMemberRepository: InMemoryStaffMemberRepository(),
        sessionDuration: () => const Duration(hours: 1),
        claimsSyncClient: claimsSyncClient,
        organizationId: () => _testOrgId,
      );
      const current = ActorSession(
        actorId: 'uid-1',
        roles: {StaffRole.manager},
        activeRole: StaffRole.manager,
        branchAccess: {},
      );

      final refreshed = await repository.refreshSession(current);

      expect(refreshed, isNotNull);
      expect(refreshed!.branchAccess, {'branch-1', 'branch-2'});
    });

    test(
        'a resynced staff member who lost every role loses UI access '
        'after refresh (claims resolve to empty -> session becomes null)',
        () async {
      final repository = FirebaseStaffAuthRepository(
        authClient: FakeEmailPasswordAuthClient(),
        staffMemberRepository: InMemoryStaffMemberRepository(),
        sessionDuration: () => const Duration(hours: 1),
        claimsSyncClient: FakeStaffClaimsSyncClient(), // empty claims
        organizationId: () => _testOrgId,
      );
      const current = ActorSession(
        actorId: 'uid-1',
        roles: {StaffRole.manager},
        activeRole: StaffRole.manager,
      );

      final refreshed = await repository.refreshSession(current);

      expect(refreshed, isNull);
    });

    test(
        'an active role no longer held falls back to the first role still '
        'held, mirroring the pre-R.3A.2 StaffMember-based behavior', () async {
      final repository = FirebaseStaffAuthRepository(
        authClient: FakeEmailPasswordAuthClient(),
        staffMemberRepository: InMemoryStaffMemberRepository(),
        sessionDuration: () => const Duration(hours: 1),
        claimsSyncClient: FakeStaffClaimsSyncClient(
          claimsToReturn: const StaffAuthorizationClaims(
            organizationAccess: [_testOrgId],
            rolesByOrganization: {
              _testOrgId: ['staff'],
            },
            branchAccessByOrganization: {},
          ),
        ),
        organizationId: () => _testOrgId,
      );
      const current = ActorSession(
        actorId: 'uid-1',
        roles: {StaffRole.manager},
        activeRole: StaffRole.manager,
      );

      final refreshed = await repository.refreshSession(current);

      expect(refreshed, isNotNull);
      expect(refreshed!.roles, {StaffRole.staff});
      expect(refreshed.activeRole, StaffRole.staff);
    });

    test(
        'a forced session revocation (StaffMember.sessionsRevokedAt) still '
        'denies, even when claims independently still carry a role — an '
        'additional, best-effort deny path, never a grant path', () async {
      final memberRepository = InMemoryStaffMemberRepository();
      await memberRepository.save(buildTestStaffMember(
        id: 'uid-1',
        roles: {StaffRole.manager},
        sessionsRevokedAt: DateTime(2026, 1, 1),
      ));
      final repository = FirebaseStaffAuthRepository(
        authClient: FakeEmailPasswordAuthClient(),
        staffMemberRepository: memberRepository,
        sessionDuration: () => const Duration(hours: 1),
        claimsSyncClient: FakeStaffClaimsSyncClient(
          claimsToReturn: const StaffAuthorizationClaims(
            organizationAccess: [_testOrgId],
            rolesByOrganization: {
              _testOrgId: ['manager'],
            },
            branchAccessByOrganization: {},
          ),
        ),
        organizationId: () => _testOrgId,
      );
      final current = ActorSession(
        actorId: 'uid-1',
        roles: const {StaffRole.manager},
        activeRole: StaffRole.manager,
        issuedAt: DateTime(2025, 1, 1), // before sessionsRevokedAt
      );

      final refreshed = await repository.refreshSession(current);

      expect(refreshed, isNull);
    });

    test(
        'a StaffMemberRepository lookup that throws never denies or hangs '
        'refreshSession either — same best-effort-only guarantee as signIn',
        () async {
      final repository = FirebaseStaffAuthRepository(
        authClient: FakeEmailPasswordAuthClient(),
        staffMemberRepository: _ThrowingStaffMemberRepository(),
        sessionDuration: () => const Duration(hours: 1),
        claimsSyncClient: FakeStaffClaimsSyncClient(
          claimsToReturn: const StaffAuthorizationClaims(
            organizationAccess: [_testOrgId],
            rolesByOrganization: {
              _testOrgId: ['manager'],
            },
            branchAccessByOrganization: {},
          ),
        ),
        organizationId: () => _testOrgId,
      );
      const current = ActorSession(
        actorId: 'uid-1',
        roles: {StaffRole.manager},
        activeRole: StaffRole.manager,
      );

      final refreshed = await repository.refreshSession(current);

      expect(refreshed, isNotNull);
      expect(refreshed!.roles, {StaffRole.manager});
    });
  });
}

/// Simulates a slow/unavailable staff directory (e.g. a Firestore query
/// that times out) — every method throws, proving `signIn`/`refreshSession`
/// treat this repository as best-effort profile metadata only, never as an
/// authorization gate.
class _ThrowingStaffMemberRepository implements StaffMemberRepository {
  @override
  Future<void> save(StaffMember member) =>
      throw Exception('directory unavailable');

  @override
  Future<StaffMember?> findById(String staffMemberId) =>
      throw Exception('directory unavailable');

  @override
  Future<StaffMember?> findByAuthUid(String authUid) =>
      throw Exception('directory unavailable');

  @override
  Future<List<StaffMember>> findAll() =>
      throw Exception('directory unavailable');

  @override
  Future<List<StaffMember>> findByBranch(String branchId) =>
      throw Exception('directory unavailable');

  @override
  Future<StaffMember> register({
    required String displayName,
    required String email,
  }) =>
      throw Exception('directory unavailable');
}
