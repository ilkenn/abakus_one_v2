import 'dart:convert';

import 'package:abakus_one_v2/core/services/auth/staff_claims_sync_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a syntactically-real (unsigned) JWT string for [decodeJwtPayload]
/// to decode — the signature segment's actual content doesn't matter here,
/// since this function never verifies it (that's the server's job, always);
/// only the header/payload segments' base64url-JSON shape does.
String _fakeJwt(Map<String, dynamic> payload, {String header = 'header'}) {
  String segment(Object value) =>
      base64Url.encode(utf8.encode(value is String ? value : jsonEncode(value)))
          .replaceAll('=', '');
  return '${segment(header)}.${segment(payload)}.signature';
}

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

  group('decodeJwtPayload', () {
    test(
        'decodes a real-shaped JWT\'s payload, including custom claims '
        'merged at the top level — the exact fallback path for Windows\'s '
        'null IdTokenResult.claims (PC Yönetici İnceleme Modu, 2026-09-21)',
        () {
      final jwt = _fakeJwt({
        'iss': 'https://securetoken.google.com/demo-project',
        'sub': 'uid-123',
        'organizationAccess': ['org-1'],
        'roles': {
          'org-1': ['admin'],
        },
      });

      final result = decodeJwtPayload(jwt);

      expect(result, isNotNull);
      expect(result!['organizationAccess'], ['org-1']);
      expect(result['roles'], {
        'org-1': ['admin'],
      });
    });

    test('a payload segment missing base64 padding still decodes', () {
      // base64url.normalize's whole job — a real JWT payload's length is
      // essentially never a multiple of 4, so padding is routinely absent.
      final jwt = _fakeJwt({'a': 1});

      expect(decodeJwtPayload(jwt), {'a': 1});
    });

    test('a string with the wrong number of dot-separated segments returns '
        'null, never throws', () {
      expect(decodeJwtPayload('not-a-jwt'), isNull);
      expect(decodeJwtPayload('only.two'), isNull);
      expect(decodeJwtPayload('four.segments.here.oops'), isNull);
    });

    test('a payload segment that decodes to non-base64/non-JSON returns '
        'null, never throws', () {
      expect(decodeJwtPayload('header.!!!not-base64!!!.signature'), isNull);
    });

    test('a payload that is valid JSON but not a JSON object returns null',
        () {
      final arrayPayload =
          base64Url.encode(utf8.encode('[1,2,3]')).replaceAll('=', '');
      expect(decodeJwtPayload('header.$arrayPayload.signature'), isNull);
    });
  });
}
