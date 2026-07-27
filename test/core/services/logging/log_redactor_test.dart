import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/core/services/logging/log_redactor.dart';

void main() {
  group('LogRedactor.redactContext', () {
    test('redacts a value whose key matches a sensitive marker', () {
      final result = LogRedactor.redactContext({'token': 'abc123'});
      expect(result['token'], LogRedactor.redactedValue);
    });

    test('matching is case-insensitive', () {
      final result = LogRedactor.redactContext({
        'ACCESS_TOKEN': 'abc123',
        'Password': 'hunter2',
        'otpCode': '482913',
      });

      expect(result['ACCESS_TOKEN'], LogRedactor.redactedValue);
      expect(result['Password'], LogRedactor.redactedValue);
      expect(result['otpCode'], LogRedactor.redactedValue);
    });

    test('matches a key that merely contains a sensitive substring', () {
      final result = LogRedactor.redactContext({
        'userPhoneNumber': '+905321234567',
        'cardNumber': '4111111111111111',
        'userEmailAddress': 'test@example.com',
      });

      expect(result['userPhoneNumber'], LogRedactor.redactedValue);
      expect(result['cardNumber'], LogRedactor.redactedValue);
      expect(result['userEmailAddress'], LogRedactor.redactedValue);
    });

    test('leaves a non-sensitive key/value untouched', () {
      final result = LogRedactor.redactContext({
        'orderId': 'ord_123',
        'screen': 'CheckoutScreen',
        'itemCount': 3,
      });

      expect(result['orderId'], 'ord_123');
      expect(result['screen'], 'CheckoutScreen');
      expect(result['itemCount'], 3);
    });

    test('never removes or renames a key, even a sensitive one', () {
      final result = LogRedactor.redactContext({'token': 'abc123'});
      expect(result.containsKey('token'), isTrue);
      expect(result.length, 1);
    });

    test('an empty map redacts to an empty map', () {
      expect(LogRedactor.redactContext({}), isEmpty);
    });

    test('a mixed map only redacts the sensitive entries', () {
      final result = LogRedactor.redactContext({
        'orderId': 'ord_123',
        'password': 'hunter2',
      });

      expect(result['orderId'], 'ord_123');
      expect(result['password'], LogRedactor.redactedValue);
    });
  });

  group('LogRedactor.sanitizeText', () {
    test('redacts a Bearer token', () {
      final result = LogRedactor.sanitizeText(
        'Authorization header: Bearer eyJhbGciOiJIUzI1NiJ9.abc.def',
      );

      expect(result, isNot(contains('eyJhbGciOiJIUzI1NiJ9')));
      expect(result, contains('Bearer ${LogRedactor.redactedValue}'));
    });

    test('Bearer matching is case-insensitive', () {
      final result = LogRedactor.sanitizeText('bearer abc123xyz');
      expect(result, isNot(contains('abc123xyz')));
    });

    test('redacts a labeled token value (key=value shape)', () {
      final result =
          LogRedactor.sanitizeText('request failed: token=abc123xyz');
      expect(result, isNot(contains('abc123xyz')));
      expect(result, contains(LogRedactor.redactedValue));
    });

    test('redacts a labeled password value (key: value shape)', () {
      final result =
          LogRedactor.sanitizeText('login attempt password: hunter2');
      expect(result, isNot(contains('hunter2')));
      expect(result, contains(LogRedactor.redactedValue));
    });

    test('redacts a labeled OTP value', () {
      final result = LogRedactor.sanitizeText('otp verification otp=482913');
      expect(result, isNot(contains('482913')));
      expect(result, contains(LogRedactor.redactedValue));
    });

    test('redacts a labeled PIN and CVV value', () {
      final pinResult = LogRedactor.sanitizeText('card pin=1234 entered');
      final cvvResult = LogRedactor.sanitizeText('cvv: 123 submitted');

      expect(pinResult, isNot(contains('1234')));
      expect(cvvResult, isNot(contains('123 submitted')));
    });

    test('redacts an email address', () {
      final result = LogRedactor.sanitizeText(
        'password reset requested for kullanici@example.com',
      );

      expect(result, isNot(contains('kullanici@example.com')));
      expect(result, contains(LogRedactor.redactedValue));
    });

    test('redacts a phone-number-shaped digit run', () {
      final result = LogRedactor.sanitizeText(
        'OTP sent to +905321234567 successfully',
      );

      expect(result, isNot(contains('905321234567')));
      expect(result, contains(LogRedactor.redactedValue));
    });

    test('redacts a card-number-shaped digit run', () {
      final result = LogRedactor.sanitizeText(
        'payment attempted with 4111 1111 1111 1111',
      );

      expect(result, isNot(contains('4111 1111 1111 1111')));
      expect(result, contains(LogRedactor.redactedValue));
    });

    test('leaves ordinary text with no sensitive shape untouched', () {
      const text = 'user tapped checkout on OrderSummaryScreen';
      expect(LogRedactor.sanitizeText(text), text);
    });

    test('redacts every sensitive shape present in a single message', () {
      final result = LogRedactor.sanitizeText(
        'user test@example.com failed login: password=hunter2, '
        'phone +905321234567, Bearer abc.def.ghi',
      );

      expect(result, isNot(contains('test@example.com')));
      expect(result, isNot(contains('hunter2')));
      expect(result, isNot(contains('905321234567')));
      expect(result, isNot(contains('abc.def.ghi')));
    });

    test('an empty string sanitizes to an empty string', () {
      expect(LogRedactor.sanitizeText(''), '');
    });
  });
}
