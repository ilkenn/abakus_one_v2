import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/core/errors/error_mapper.dart';
import 'package:abakus_one_v2/core/errors/failure.dart';

/// A stand-in for `dart:io`'s `SocketException` — same runtime-type
/// *name*, deliberately not the real class (see `error_mapper.dart`'s doc
/// comment on why `dart:io` isn't imported). [ErrorMapper] recognizes
/// connectivity exceptions by type name, so this is enough to exercise
/// that branch without depending on `dart:io`.
class SocketException implements Exception {
  const SocketException(this._message);
  final String _message;
  @override
  String toString() => 'SocketException: $_message';
}

class HttpException implements Exception {
  const HttpException(this._message);
  final String _message;
  @override
  String toString() => 'HttpException: $_message';
}

class WebSocketException implements Exception {
  @override
  String toString() => 'WebSocketException';
}

class ClientException implements Exception {
  @override
  String toString() => 'ClientException';
}

class _UnrecognizedException implements Exception {
  @override
  String toString() => '_UnrecognizedException';
}

void main() {
  group('ErrorMapper.map — recognized exception types', () {
    test('TimeoutException maps to TimeoutFailure', () {
      final exception = TimeoutException('too slow');
      final failure = ErrorMapper.map(exception);

      expect(failure, isA<TimeoutFailure>());
      expect(failure.message, isNotEmpty);
      expect(failure.debugMessage, exception.toString());
    });

    test('FormatException maps to ValidationFailure', () {
      const exception = FormatException('bad input');
      final failure = ErrorMapper.map(exception);

      expect(failure, isA<ValidationFailure>());
      expect(failure.message, isNotEmpty);
      expect(failure.debugMessage, exception.toString());
    });

    test(
        'PlatformException maps to UnexpectedFailure with code preserved '
        'in debugMessage only', () {
      final exception = PlatformException(
        code: 'UNAVAILABLE',
        message: 'channel not available',
      );
      final failure = ErrorMapper.map(exception);

      expect(failure, isA<UnexpectedFailure>());
      expect(failure.message, isNotEmpty);
      expect(failure.message, isNot(contains('UNAVAILABLE')));
      expect(failure.debugMessage, contains('UNAVAILABLE'));
    });

    test('SocketException-shaped errors map to NetworkFailure', () {
      final failure = ErrorMapper.map(const SocketException('refused'));
      expect(failure, isA<NetworkFailure>());
    });

    test('HttpException-shaped errors map to NetworkFailure', () {
      final failure = ErrorMapper.map(const HttpException('502'));
      expect(failure, isA<NetworkFailure>());
    });

    test('WebSocketException-shaped errors map to NetworkFailure', () {
      final failure = ErrorMapper.map(WebSocketException());
      expect(failure, isA<NetworkFailure>());
    });

    test('ClientException-shaped errors map to NetworkFailure', () {
      final failure = ErrorMapper.map(ClientException());
      expect(failure, isA<NetworkFailure>());
    });
  });

  group('ErrorMapper.map — unknown-error fallback', () {
    test(
        'an unrecognized custom exception maps deterministically to '
        'UnexpectedFailure', () {
      final failure = ErrorMapper.map(_UnrecognizedException());
      expect(failure, isA<UnexpectedFailure>());
      expect(failure.debugMessage, '_UnrecognizedException');
    });

    test('a bare Exception maps to UnexpectedFailure', () {
      final failure = ErrorMapper.map(Exception('generic'));
      expect(failure, isA<UnexpectedFailure>());
    });

    test('an Error (not an Exception) still maps deterministically', () {
      final failure = ErrorMapper.map(StateError('bad state'));
      expect(failure, isA<UnexpectedFailure>());
    });

    test('a plain Object maps to UnexpectedFailure without throwing', () {
      expect(() => ErrorMapper.map(Object()), returnsNormally);
      expect(ErrorMapper.map(Object()), isA<UnexpectedFailure>());
    });

    test('mapping never throws for any input', () {
      final inputs = <Object>[
        'a raw string',
        42,
        Exception('x'),
        StateError('y'),
        Object(),
      ];
      for (final input in inputs) {
        expect(() => ErrorMapper.map(input), returnsNormally);
      }
    });
  });

  group('ErrorMapper.map — usable without any framework dependency', () {
    test('is a plain static function call, no BuildContext/setup required', () {
      final failure = ErrorMapper.map(Exception('no context needed'));
      expect(failure, isNotNull);
    });
  });
}
