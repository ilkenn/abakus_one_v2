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
}
