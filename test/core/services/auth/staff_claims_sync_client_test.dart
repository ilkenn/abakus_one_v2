import 'package:abakus_one_v2/core/services/auth/staff_claims_sync_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// Faz R.3A.2 — proves `parseStaffAuthorizationClaims` degrades to
/// [StaffAuthorizationClaims.empty] on any missing/malformed shape rather
/// than throwing, satisfying "missing or malformed claims denies safely"
/// at the parsing layer itself (before [ActorSession.tryFromRaw] even gets
/// a chance to apply its own empty-roles-denies-safely rule downstream).
///
/// Faz R.3C.2 extends this to the `branchAccess` claim — parsed via the
/// identical `Record<organizationId, string[]>` shape `roles` already
/// uses, so every failure mode `roles` is proven safe against is proven
/// for `branchAccess` here too.
void main() {
  group('parseStaffAuthorizationClaims', () {
    test('null claims map parses to empty', () {
      final result = parseStaffAuthorizationClaims(null);

      expect(result.organizationAccess, isEmpty);
      expect(result.rolesByOrganization, isEmpty);
      expect(result.branchAccessByOrganization, isEmpty);
    });

    test('a claims map missing all keys parses to empty', () {
      final result = parseStaffAuthorizationClaims(const {});

      expect(result.organizationAccess, isEmpty);
      expect(result.rolesByOrganization, isEmpty);
      expect(result.branchAccessByOrganization, isEmpty);
    });

    test('a well-formed claims map parses exactly', () {
      final result = parseStaffAuthorizationClaims(const {
        'organizationAccess': ['org-1'],
        'roles': {
          'org-1': ['manager', 'admin'],
        },
        'branchAccess': {
          'org-1': ['branch-1', 'branch-2'],
        },
      });

      expect(result.organizationAccess, ['org-1']);
      expect(result.rolesFor('org-1'), ['manager', 'admin']);
      expect(result.branchAccessFor('org-1'), ['branch-1', 'branch-2']);
    });

    test(
        'organizationAccess of the wrong type (not a List) parses to '
        'empty rather than throwing', () {
      final result = parseStaffAuthorizationClaims(const {
        'organizationAccess': 'org-1', // malformed: a bare string, not a List
        'roles': <String, dynamic>{},
      });

      expect(result.organizationAccess, isEmpty);
    });

    test(
        'roles of the wrong type (not a Map) parses to empty rather than '
        'throwing', () {
      final result = parseStaffAuthorizationClaims(const {
        'organizationAccess': ['org-1'],
        'roles': ['manager'], // malformed: a List, not a Map
      });

      expect(result.rolesByOrganization, isEmpty);
    });

    test(
        'branchAccess of the wrong type (not a Map) parses to empty rather '
        'than throwing — fails closed, not "every branch"', () {
      final result = parseStaffAuthorizationClaims(const {
        'organizationAccess': ['org-1'],
        'branchAccess': 'branch-1', // malformed: a bare string, not a Map
      });

      expect(result.branchAccessByOrganization, isEmpty);
      expect(result.branchAccessFor('org-1'), isEmpty);
    });

    test('a non-string organizationAccess entry is dropped, not thrown', () {
      final result = parseStaffAuthorizationClaims(const {
        'organizationAccess': ['org-1', 42, null],
      });

      expect(result.organizationAccess, ['org-1']);
    });

    test('a roles entry whose value is not a List is dropped, not thrown', () {
      final result = parseStaffAuthorizationClaims(const {
        'roles': {
          'org-1': ['manager'],
          'org-2': 'not-a-list',
        },
      });

      expect(result.rolesFor('org-1'), ['manager']);
      expect(result.rolesFor('org-2'), isEmpty);
    });

    test(
        'a branchAccess entry whose value is not a List is dropped, not '
        'thrown — that organization fails closed to zero branch access', () {
      final result = parseStaffAuthorizationClaims(const {
        'branchAccess': {
          'org-1': ['branch-1'],
          'org-2': 'not-a-list',
        },
      });

      expect(result.branchAccessFor('org-1'), ['branch-1']);
      expect(result.branchAccessFor('org-2'), isEmpty);
    });

    test(
        'a non-string role entry within a valid list is dropped, not '
        'thrown', () {
      final result = parseStaffAuthorizationClaims(const {
        'roles': {
          'org-1': ['manager', 7, null],
        },
      });

      expect(result.rolesFor('org-1'), ['manager']);
    });

    test(
        'a non-string branchId entry within a valid list is dropped, not '
        'thrown', () {
      final result = parseStaffAuthorizationClaims(const {
        'branchAccess': {
          'org-1': ['branch-1', 7, null],
        },
      });

      expect(result.branchAccessFor('org-1'), ['branch-1']);
    });
  });

  group('StaffAuthorizationClaims.rolesFor', () {
    test(
        'an organization with no entry at all returns an empty list, '
        'never a null-shaped "trust everything" fallback', () {
      const claims = StaffAuthorizationClaims(
        organizationAccess: ['org-1'],
        rolesByOrganization: {},
        branchAccessByOrganization: {},
      );

      expect(claims.rolesFor('org-1'), isEmpty);
      expect(claims.rolesFor('unknown-org'), isEmpty);
    });
  });

  group('StaffAuthorizationClaims.branchAccessFor', () {
    test(
        'an organization with no branchAccess entry at all returns an '
        'empty list — missing means zero branch access, never "every '
        'branch" (Faz R.3C.2)', () {
      const claims = StaffAuthorizationClaims(
        organizationAccess: ['org-1'],
        rolesByOrganization: {
          'org-1': ['admin'],
        },
        branchAccessByOrganization: {},
      );

      expect(claims.branchAccessFor('org-1'), isEmpty,
          reason: 'even an admin role must not implicitly grant every branch — '
              'this membership model has no role-based branch bypass');
      expect(claims.branchAccessFor('unknown-org'), isEmpty);
    });
  });
}
