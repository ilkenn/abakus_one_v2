import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/customer_photos/data/customer_photo_gateway.dart';

/// Profile P.4.3A — Upload Grant Callable Response Diagnostic (2026-08-19).
///
/// A physical Android device isolated the stall to exactly this boundary:
/// `requestCustomerPhotoUploadGrant` completes successfully server-side
/// (confirmed via the Functions Emulator's own log), but Flutter never
/// logs "upload grant received" — the callable's raw response resolves,
/// yet the parse into [CustomerPhotoUploadGrant] apparently never
/// completes either. These tests trace the EXACT contract between the
/// Function's actual return shape (`functions/src/customerPhotoUploadGrants
/// .ts`'s `RequestUploadGrantResult`) and [parseCustomerPhotoUploadGrant],
/// independent of the real callable SDK (unavailable under `flutter test`).
void main() {
  group('parseCustomerPhotoUploadGrant', () {
    Map<String, dynamic> validResponse(
        {Object? expiresAtMillis = 1755647700000}) {
      return {
        'grantId': 'grant-abc123',
        'objectPath':
            'tenants/org-1/customerPhotos/customer-uid-1/grant-abc123',
        'contentType': 'image/jpeg',
        'expiresAtMillis': expiresAtMillis,
        'reused': false,
      };
    }

    test(
        'parses a response where expiresAtMillis arrives as a Dart int '
        '(the value shape produced on most platforms)', () {
      final grant = parseCustomerPhotoUploadGrant(
          validResponse(expiresAtMillis: 1755647700000));

      expect(grant.grantId, 'grant-abc123');
      expect(grant.objectPath,
          'tenants/org-1/customerPhotos/customer-uid-1/grant-abc123');
      expect(grant.contentType, 'image/jpeg');
      expect(
          grant.expiresAt, DateTime.fromMillisecondsSinceEpoch(1755647700000));
    });

    test(
        'parses a response where expiresAtMillis arrives as a Dart double '
        '— the exact shape the Android callable SDK\'s generic JSON '
        'decoding can produce for a whole-number field, and the leading '
        'hypothesis for this physical-device stall', () {
      final grant = parseCustomerPhotoUploadGrant(
        validResponse(expiresAtMillis: 1755647700000.0),
      );

      expect(
          grant.expiresAt, DateTime.fromMillisecondsSinceEpoch(1755647700000));
    });

    test(
        'throws a descriptive FormatException — never an uncaught TypeError '
        '— when expiresAtMillis is missing or the wrong type entirely', () {
      expect(
        () => parseCustomerPhotoUploadGrant(
          validResponse(expiresAtMillis: null),
        ),
        throwsFormatException,
      );
      expect(
        () => parseCustomerPhotoUploadGrant(
          validResponse(expiresAtMillis: '1755647700000'),
        ),
        throwsFormatException,
      );
    });

    test(
        'the exact field set the Function actually returns is exactly '
        'what this parser reads — grantId/objectPath/contentType/'
        'expiresAtMillis; reused is present but intentionally unused', () {
      // Mirrors functions/src/customerPhotoUploadGrants.ts's
      // RequestUploadGrantResult shape exactly, including the field this
      // parser does NOT consume (reused) — proving an extra field never
      // breaks parsing.
      final grant = parseCustomerPhotoUploadGrant({
        'grantId': 'g1',
        'objectPath': 'tenants/org-1/customerPhotos/uid/g1',
        'expiresAtMillis': 123,
        'contentType': 'image/png',
        'reused': true,
      });

      expect(grant.grantId, 'g1');
    });
  });

  group('buildGrantCallableResponseLogContext', () {
    test(
        'reports the runtime type of the payload, its keys, and each '
        'expected field\'s runtime type — never a value', () {
      final context = buildGrantCallableResponseLogContext({
        'grantId': 'g1',
        'objectPath': 'tenants/org-1/customerPhotos/uid/g1',
        'contentType': 'image/png',
        'expiresAtMillis': 1755647700000.0,
      });

      expect(context['dataRuntimeType'], contains('Map'));
      expect(
          context['mapKeys'],
          containsAll(<String>[
            'grantId',
            'objectPath',
            'contentType',
            'expiresAtMillis'
          ]));
      expect(context['grantIdType'], 'String');
      expect(context['expiresAtMillisType'], 'double');
    });

    test(
        'reports "missing" for an expected field the response omits '
        'entirely, and "null" for one explicitly present but null', () {
      final context = buildGrantCallableResponseLogContext({
        'grantId': 'g1',
        'expiresAtMillis': null,
      });

      expect(context['objectPathType'], 'missing');
      expect(context['expiresAtMillisType'], 'null');
    });

    test('degrades safely for a non-Map payload instead of throwing', () {
      final context = buildGrantCallableResponseLogContext('unexpected-string');

      expect(context['dataRuntimeType'], contains('String'));
      expect(context['mapKeys'], isEmpty);
      expect(context['grantIdType'], 'missing');
    });

    test('never includes an actual field value — only type/key names', () {
      const secretLookingValue =
          'tenants/org-1/customerPhotos/uid/should-not-appear';
      final context = buildGrantCallableResponseLogContext({
        'objectPath': secretLookingValue,
      });

      expect(context.values, isNot(contains(secretLookingValue)));
    });
  });
}
