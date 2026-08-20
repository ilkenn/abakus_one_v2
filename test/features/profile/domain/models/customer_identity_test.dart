import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/profile/domain/models/customer_identity.dart';

void main() {
  group('parseCustomerOccupationStatus', () {
    test('working', () {
      expect(parseCustomerOccupationStatus('working'),
          CustomerOccupationStatus.working);
    });

    test('student', () {
      expect(parseCustomerOccupationStatus('student'),
          CustomerOccupationStatus.student);
    });

    test('other', () {
      expect(parseCustomerOccupationStatus('other'),
          CustomerOccupationStatus.other);
    });

    test('null -> unknown, never throws', () {
      expect(parseCustomerOccupationStatus(null),
          CustomerOccupationStatus.unknown);
    });

    test('an unrecognized raw value -> unknown, never throws', () {
      expect(parseCustomerOccupationStatus('something-new'),
          CustomerOccupationStatus.unknown);
    });
  });

  group('CustomerIdentity.fullName', () {
    test('joins firstName and lastName with a single space', () {
      const identity = CustomerIdentity(
        firstName: 'İlken',
        lastName: 'Parlakbudak',
        email: 'ilken@example.com',
        occupationStatus: CustomerOccupationStatus.working,
      );
      expect(identity.fullName, 'İlken Parlakbudak');
    });

    test('both empty -> empty string, never a fabricated placeholder', () {
      const identity = CustomerIdentity(
        firstName: '',
        lastName: '',
        email: '',
        occupationStatus: CustomerOccupationStatus.unknown,
      );
      expect(identity.fullName, '');
    });
  });

  group('CustomerIdentity.initials', () {
    test('first letter of each name, uppercased', () {
      const identity = CustomerIdentity(
        firstName: 'ahmet',
        lastName: 'yılmaz',
        email: '',
        occupationStatus: CustomerOccupationStatus.student,
      );
      expect(identity.initials, 'AY');
    });

    test('both names empty -> empty string (caller falls back to an icon)', () {
      const identity = CustomerIdentity(
        firstName: '',
        lastName: '',
        email: '',
        occupationStatus: CustomerOccupationStatus.unknown,
      );
      expect(identity.initials, '');
    });

    test('only firstName present -> single initial, never throws', () {
      const identity = CustomerIdentity(
        firstName: 'Ahmet',
        lastName: '',
        email: '',
        occupationStatus: CustomerOccupationStatus.other,
      );
      expect(identity.initials, 'A');
    });
  });
}
