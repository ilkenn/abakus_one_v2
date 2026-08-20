import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/customer_registration/data/customer_registration_gateway.dart';

/// Customer Registration CR.1 — traces the exact return contract between
/// `completeCustomerProfile`'s decoded callable response and
/// [parseCompleteCustomerProfileResult], mirroring
/// `parseCustomerPhotoUploadGrant`'s own established pure-function test
/// pattern (this session's hard-won "never assume a wire value's Dart
/// runtime type" lesson, applied here too).
void main() {
  group('parseCompleteCustomerProfileResult', () {
    test('parses a well-formed response', () {
      final result = parseCompleteCustomerProfileResult({
        'alreadyCompleted': false,
        'organizationId': 'org-1',
      });
      expect(result.alreadyCompleted, isFalse);
      expect(result.organizationId, 'org-1');
    });

    test('parses alreadyCompleted: true', () {
      final result = parseCompleteCustomerProfileResult({
        'alreadyCompleted': true,
        'organizationId': 'org-1',
      });
      expect(result.alreadyCompleted, isTrue);
    });

    test(
        'throws a FormatException — never an uncaught TypeError — when alreadyCompleted is missing or the wrong type',
        () {
      expect(
        () => parseCompleteCustomerProfileResult({'organizationId': 'org-1'}),
        throwsFormatException,
      );
      expect(
        () => parseCompleteCustomerProfileResult({
          'alreadyCompleted': 'false',
          'organizationId': 'org-1',
        }),
        throwsFormatException,
      );
    });

    test(
        'throws a FormatException when organizationId is missing or the wrong type',
        () {
      expect(
        () => parseCompleteCustomerProfileResult({'alreadyCompleted': false}),
        throwsFormatException,
      );
      expect(
        () => parseCompleteCustomerProfileResult({
          'alreadyCompleted': false,
          'organizationId': 123,
        }),
        throwsFormatException,
      );
    });
  });

  group('parseCustomerProfileCompletionResult', () {
    test('parses state: complete, with no reason', () {
      final result =
          parseCustomerProfileCompletionResult({'state': 'complete'});
      expect(result.isComplete, isTrue);
      expect(result.reason, isNull);
    });

    test('parses state: incomplete with a reason', () {
      final result = parseCustomerProfileCompletionResult({
        'state': 'incomplete',
        'reason': 'membershipMissing',
      });
      expect(result.isComplete, isFalse);
      expect(result.reason, 'membershipMissing');
    });

    test('parses state: incomplete with no reason present', () {
      final result =
          parseCustomerProfileCompletionResult({'state': 'incomplete'});
      expect(result.isComplete, isFalse);
      expect(result.reason, isNull);
    });

    test(
        'throws a FormatException for a missing or unrecognized state value — never silently defaults',
        () {
      expect(
        () => parseCustomerProfileCompletionResult({}),
        throwsFormatException,
      );
      expect(
        () => parseCustomerProfileCompletionResult({'state': 'unknown'}),
        throwsFormatException,
      );
      expect(
        () => parseCustomerProfileCompletionResult({'state': true}),
        throwsFormatException,
      );
    });

    test('throws a FormatException when reason is present but not a string',
        () {
      expect(
        () => parseCustomerProfileCompletionResult({
          'state': 'incomplete',
          'reason': 42,
        }),
        throwsFormatException,
      );
    });
  });

  group('CustomerRegistrationGatewayException', () {
    test('carries the exact code and message given', () {
      const exception = CustomerRegistrationGatewayException(
          'invalid-argument', 'email is not valid.');
      expect(exception.code, 'invalid-argument');
      expect(exception.message, 'email is not valid.');
      expect(exception.toString(), contains('invalid-argument'));
    });
  });
}
