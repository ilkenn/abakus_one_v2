import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/customer_registration/domain/customer_registration_validation.dart';

/// Customer Registration CR.1 — client-side validation mirrors
/// `functions/src/completeCustomerProfile.ts`'s server-side rules
/// field-for-field. These tests exercise that mirror directly, plus the
/// exhaustive `isCustomerProfileComplete` completeness definition the
/// audit's own locked instruction requires (never decided solely by
/// tenant membership existence).
void main() {
  group('validateRequiredName', () {
    test('a valid name passes', () {
      expect(validateRequiredName('Ayşe', fieldLabel: 'Ad'), isNull);
    });

    test('null is rejected', () {
      expect(validateRequiredName(null, fieldLabel: 'Ad'), isNotNull);
    });

    test('blank-only whitespace is rejected — never a fake default name', () {
      expect(validateRequiredName('   ', fieldLabel: 'Ad'), isNotNull);
    });

    test('a name over the max length is rejected', () {
      final tooLong = 'A' * (kMaxNameLength + 1);
      expect(validateRequiredName(tooLong, fieldLabel: 'Ad'), isNotNull);
    });

    test('a name at exactly the max length passes', () {
      final exact = 'A' * kMaxNameLength;
      expect(validateRequiredName(exact, fieldLabel: 'Ad'), isNull);
    });
  });

  group('validateEmail', () {
    test('a valid email passes', () {
      expect(validateEmail('ayse@example.com'), isNull);
    });

    test('missing @ is rejected', () {
      expect(validateEmail('not-an-email'), isNotNull);
    });

    test('missing domain dot is rejected', () {
      expect(validateEmail('ayse@example'), isNotNull);
    });

    test('empty/blank is rejected', () {
      expect(validateEmail(''), isNotNull);
      expect(validateEmail('   '), isNotNull);
    });

    test('over the RFC 5321 max length is rejected', () {
      final tooLong = '${'a' * (kMaxEmailLength)}@example.com';
      expect(validateEmail(tooLong), isNotNull);
    });
  });

  group('normalizeEmail', () {
    test('trims and lowercases', () {
      expect(normalizeEmail('  Ayse.Yilmaz@EXAMPLE.com  '),
          'ayse.yilmaz@example.com');
    });
  });

  group('validateInstitutionField', () {
    test('a valid institution name passes', () {
      expect(
        validateInstitutionField('Kabataş Erkek Lisesi',
            fieldLabel: 'Okul / Eğitim Kurumu'),
        isNull,
      );
    });

    test('blank is rejected', () {
      expect(
        validateInstitutionField('', fieldLabel: 'Okul / Eğitim Kurumu'),
        isNotNull,
      );
    });

    test('over the max length is rejected', () {
      final tooLong = 'A' * (kMaxInstitutionLength + 1);
      expect(
        validateInstitutionField(tooLong, fieldLabel: 'Şirket / İş Yeri'),
        isNotNull,
      );
    });
  });

  group('formatCanonicalBirthDate', () {
    test('formats a date as zero-padded YYYY-MM-DD', () {
      expect(formatCanonicalBirthDate(DateTime(1990, 8, 20)), '1990-08-20');
    });

    test('zero-pads single-digit month and day', () {
      expect(formatCanonicalBirthDate(DateTime(2001, 1, 5)), '2001-01-05');
    });

    test('never includes a time-of-day or timezone suffix', () {
      final formatted = formatCanonicalBirthDate(DateTime(1990, 8, 20, 13, 45));
      expect(formatted, '1990-08-20');
      expect(formatted.contains(':'), isFalse);
      expect(formatted.contains('T'), isFalse);
      expect(formatted.contains('Z'), isFalse);
    });
  });

  group('validateBirthDate', () {
    test('null is rejected — required', () {
      expect(validateBirthDate(null), isNotNull);
    });

    test('a valid past date passes', () {
      expect(validateBirthDate(DateTime(1990, 8, 20)), isNull);
    });

    test('today passes', () {
      final now = DateTime.now();
      expect(validateBirthDate(DateTime(now.year, now.month, now.day)), isNull);
    });

    test('a future date is rejected', () {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      expect(validateBirthDate(tomorrow), isNotNull);
    });

    test('a year before kMinBirthYear is rejected', () {
      expect(validateBirthDate(DateTime(kMinBirthYear - 1, 1, 1)), isNotNull);
    });

    test('exactly kMinBirthYear passes', () {
      expect(validateBirthDate(DateTime(kMinBirthYear, 1, 1)), isNull);
    });
  });

  group('isCustomerProfileComplete', () {
    Map<String, dynamic> completeWorkingCustomer(
        {Map<String, dynamic>? overrides}) {
      return {
        'firstName': 'Ayşe',
        'lastName': 'Yılmaz',
        'email': 'ayse@example.com',
        'occupationStatus': 'working',
        'workplaceName': 'Abaküs Kahve',
        'gender': 'female',
        'birthDate': '1990-08-20',
        'profileCompletedAt': 'sentinel-timestamp',
        ...?overrides,
      };
    }

    test('a fully complete working customer with membership is complete', () {
      expect(
        isCustomerProfileComplete(completeWorkingCustomer(),
            membershipExists: true),
        isTrue,
      );
    });

    test('null customer data is never complete', () {
      expect(isCustomerProfileComplete(null, membershipExists: true), isFalse);
    });

    test(
        'missing tenant membership is never complete — even with an otherwise complete customer record',
        () {
      expect(
        isCustomerProfileComplete(completeWorkingCustomer(),
            membershipExists: false),
        isFalse,
      );
    });

    test('empty firstName is incomplete', () {
      expect(
        isCustomerProfileComplete(
            completeWorkingCustomer(overrides: {'firstName': ''}),
            membershipExists: true),
        isFalse,
      );
    });

    test('missing lastName is incomplete', () {
      final data = completeWorkingCustomer()..remove('lastName');
      expect(isCustomerProfileComplete(data, membershipExists: true), isFalse);
    });

    test('empty email is incomplete', () {
      expect(
        isCustomerProfileComplete(
            completeWorkingCustomer(overrides: {'email': ''}),
            membershipExists: true),
        isFalse,
      );
    });

    test('an invalid occupationStatus value is incomplete', () {
      expect(
        isCustomerProfileComplete(
          completeWorkingCustomer(overrides: {'occupationStatus': 'retired'}),
          membershipExists: true,
        ),
        isFalse,
      );
    });

    test('an invalid gender value is incomplete', () {
      expect(
        isCustomerProfileComplete(
          completeWorkingCustomer(overrides: {'gender': 'unspecified'}),
          membershipExists: true,
        ),
        isFalse,
      );
    });

    test('gender: preferNotToSay is a fully valid, complete choice', () {
      expect(
        isCustomerProfileComplete(
          completeWorkingCustomer(overrides: {'gender': 'preferNotToSay'}),
          membershipExists: true,
        ),
        isTrue,
      );
    });

    test('missing birthDate is incomplete (CR.1.1)', () {
      final data = completeWorkingCustomer()..remove('birthDate');
      expect(isCustomerProfileComplete(data, membershipExists: true), isFalse);
    });

    test('a malformed birthDate value is incomplete (CR.1.1)', () {
      expect(
        isCustomerProfileComplete(
          completeWorkingCustomer(overrides: {'birthDate': '20/08/1990'}),
          membershipExists: true,
        ),
        isFalse,
      );
    });

    test('missing profileCompletedAt is incomplete', () {
      final data = completeWorkingCustomer()..remove('profileCompletedAt');
      expect(isCustomerProfileComplete(data, membershipExists: true), isFalse);
    });

    test('occupationStatus working with a null workplaceName is incomplete',
        () {
      expect(
        isCustomerProfileComplete(
          completeWorkingCustomer(overrides: {'workplaceName': null}),
          membershipExists: true,
        ),
        isFalse,
      );
    });

    test(
        'occupationStatus student with a valid educationalInstitutionName is complete',
        () {
      final data = completeWorkingCustomer(overrides: {
        'occupationStatus': 'student',
        'workplaceName': null,
        'educationalInstitutionName': 'Kabataş Erkek Lisesi',
      });
      expect(isCustomerProfileComplete(data, membershipExists: true), isTrue);
    });

    test(
        'occupationStatus student with no educationalInstitutionName is incomplete',
        () {
      final data = completeWorkingCustomer(overrides: {
        'occupationStatus': 'student',
        'workplaceName': null,
      });
      expect(isCustomerProfileComplete(data, membershipExists: true), isFalse);
    });

    test(
        'occupationStatus other never requires workplaceName or educationalInstitutionName',
        () {
      final data = completeWorkingCustomer(overrides: {
        'occupationStatus': 'other',
        'workplaceName': null,
        'educationalInstitutionName': null,
      });
      expect(isCustomerProfileComplete(data, membershipExists: true), isTrue);
    });
  });
}
