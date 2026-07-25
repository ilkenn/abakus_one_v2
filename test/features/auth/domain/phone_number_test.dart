import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/auth/domain/phone_number.dart';

void main() {
  group('TurkishPhoneNumber.isValidLocalNumber', () {
    test('5 ile baslayan 10 haneli numarayi kabul eder', () {
      expect(TurkishPhoneNumber.isValidLocalNumber('5321234567'), isTrue);
    });

    test('5 ile baslamayan numarayi reddeder', () {
      expect(TurkishPhoneNumber.isValidLocalNumber('4321234567'), isFalse);
    });

    test('10 haneden kisa numarayi reddeder', () {
      expect(TurkishPhoneNumber.isValidLocalNumber('532123456'), isFalse);
    });

    test('10 haneden uzun numarayi reddeder', () {
      expect(TurkishPhoneNumber.isValidLocalNumber('53212345678'), isFalse);
    });

    test('bos girdiyi reddeder', () {
      expect(TurkishPhoneNumber.isValidLocalNumber(''), isFalse);
    });
  });

  group('TurkishPhoneNumber.normalize', () {
    test('gecerli numarayi +905XXXXXXXXX bicimine cevirir', () {
      expect(TurkishPhoneNumber.normalize('5321234567'), '+905321234567');
    });

    test('gorsel ayiricilari (bosluk, tire) yok sayar', () {
      expect(TurkishPhoneNumber.normalize('532 123 45 67'), '+905321234567');
    });

    test('gecersiz numara icin null doner', () {
      expect(TurkishPhoneNumber.normalize('123'), isNull);
    });
  });
}
