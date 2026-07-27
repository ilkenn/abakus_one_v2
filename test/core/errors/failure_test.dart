import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/core/errors/failure.dart';

void main() {
  group('Failure — construction', () {
    test('message is required and preserved for every subtype', () {
      const failures = <Failure>[
        ValidationFailure(message: 'a'),
        AuthenticationFailure(message: 'b'),
        AuthorizationFailure(message: 'c'),
        NetworkFailure(message: 'd'),
        TimeoutFailure(message: 'e'),
        NotFoundFailure(message: 'f'),
        ConflictFailure(message: 'g'),
        UnavailableFailure(message: 'h'),
        ConfigurationFailure(message: 'i'),
        UnexpectedFailure(message: 'j'),
      ];

      for (final failure in failures) {
        expect(failure.message, isNotEmpty);
      }
    });

    test('debugMessage defaults to null and is never required', () {
      const failure = UnexpectedFailure(message: 'Beklenmeyen bir hata.');
      expect(failure.debugMessage, isNull);
    });

    test('debugMessage is preserved when provided', () {
      const failure = NetworkFailure(
        message: 'İnternet bağlantınızı kontrol edin.',
        debugMessage: 'SocketException: Connection refused',
      );
      expect(
        failure.debugMessage,
        'SocketException: Connection refused',
      );
    });
  });

  group('Failure — equality', () {
    test('two instances of the same subtype with equal fields are equal', () {
      const a = ValidationFailure(message: 'x', debugMessage: 'y');
      const b = ValidationFailure(message: 'x', debugMessage: 'y');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differing message makes two instances unequal', () {
      const a = ValidationFailure(message: 'x');
      const b = ValidationFailure(message: 'z');
      expect(a, isNot(equals(b)));
    });

    test('differing debugMessage makes two instances unequal', () {
      const a = ValidationFailure(message: 'x', debugMessage: 'one');
      const b = ValidationFailure(message: 'x', debugMessage: 'two');
      expect(a, isNot(equals(b)));
    });

    test('same field values but a different subtype are unequal', () {
      const a = ValidationFailure(message: 'x');
      const b = NetworkFailure(message: 'x');
      expect(a, isNot(equals(b)));
    });
  });

  group('Failure — exhaustive switch (compile-time closed hierarchy)', () {
    test('every subtype is distinguishable via a switch expression', () {
      String classify(Failure failure) => switch (failure) {
            ValidationFailure() => 'validation',
            AuthenticationFailure() => 'authentication',
            AuthorizationFailure() => 'authorization',
            NetworkFailure() => 'network',
            TimeoutFailure() => 'timeout',
            NotFoundFailure() => 'notFound',
            ConflictFailure() => 'conflict',
            UnavailableFailure() => 'unavailable',
            ConfigurationFailure() => 'configuration',
            UnexpectedFailure() => 'unexpected',
          };

      expect(classify(const ValidationFailure(message: 'm')), 'validation');
      expect(
        classify(const AuthenticationFailure(message: 'm')),
        'authentication',
      );
      expect(
        classify(const AuthorizationFailure(message: 'm')),
        'authorization',
      );
      expect(classify(const NetworkFailure(message: 'm')), 'network');
      expect(classify(const TimeoutFailure(message: 'm')), 'timeout');
      expect(classify(const NotFoundFailure(message: 'm')), 'notFound');
      expect(classify(const ConflictFailure(message: 'm')), 'conflict');
      expect(
        classify(const UnavailableFailure(message: 'm')),
        'unavailable',
      );
      expect(
        classify(const ConfigurationFailure(message: 'm')),
        'configuration',
      );
      expect(classify(const UnexpectedFailure(message: 'm')), 'unexpected');
    });
  });

  group('Failure — toString', () {
    test('includes the runtime type and message for debugging', () {
      const failure = ConflictFailure(message: 'Çakışma oluştu.');
      expect(failure.toString(), contains('ConflictFailure'));
      expect(failure.toString(), contains('Çakışma oluştu.'));
    });
  });
}
