import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/core/errors/error_mapper.dart';
import 'package:abakus_one_v2/core/errors/failure.dart';

/// [FirebaseAuthException]'s own constructor is `@protected` — only
/// reachable from within its defining library or a subclass, which this
/// test-only subclass legitimately is (mirrors how the real SDK's own
/// concrete exceptions are constructed internally).
class _FakeFirebaseAuthException extends FirebaseAuthException {
  _FakeFirebaseAuthException({required super.code, super.message});
}

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

  group('ErrorMapper.map — FirebaseAuthException (Phase 9)', () {
    test('invalid-verification-code maps to ValidationFailure', () {
      final failure = ErrorMapper.map(
        _FakeFirebaseAuthException(code: 'invalid-verification-code'),
      );
      expect(failure, isA<ValidationFailure>());
    });

    test('too-many-requests maps to UnavailableFailure', () {
      final failure = ErrorMapper.map(
        _FakeFirebaseAuthException(code: 'too-many-requests'),
      );
      expect(failure, isA<UnavailableFailure>());
    });

    test('user-disabled maps to AuthorizationFailure', () {
      final failure = ErrorMapper.map(
        _FakeFirebaseAuthException(code: 'user-disabled'),
      );
      expect(failure, isA<AuthorizationFailure>());
    });

    test('session-expired maps to AuthenticationFailure', () {
      final failure = ErrorMapper.map(
        _FakeFirebaseAuthException(code: 'session-expired'),
      );
      expect(failure, isA<AuthenticationFailure>());
    });

    test('network-request-failed maps to NetworkFailure', () {
      final failure = ErrorMapper.map(
        _FakeFirebaseAuthException(code: 'network-request-failed'),
      );
      expect(failure, isA<NetworkFailure>());
    });

    test(
        'an unrecognized code still maps deterministically to '
        'AuthenticationFailure, never crashes', () {
      final failure = ErrorMapper.map(
        _FakeFirebaseAuthException(code: 'some-future-unknown-code'),
      );
      expect(failure, isA<AuthenticationFailure>());
    });

    test(
        'the vendor code is preserved in debugMessage, never in the '
        'user-facing message', () {
      final failure = ErrorMapper.map(
        _FakeFirebaseAuthException(
          code: 'user-disabled',
          message: 'The user account has been disabled.',
        ),
      );
      expect(failure.debugMessage, contains('user-disabled'));
      expect(failure.message, isNot(contains('user-disabled')));
    });
  });

  group(
      'ErrorMapper.map — FirebaseException (Phase 9, Firestore/Storage/'
      'Functions)', () {
    test('permission-denied maps to AuthorizationFailure', () {
      final failure = ErrorMapper.map(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      );
      expect(failure, isA<AuthorizationFailure>());
    });

    test('unauthenticated maps to AuthorizationFailure', () {
      final failure = ErrorMapper.map(
        FirebaseException(plugin: 'cloud_firestore', code: 'unauthenticated'),
      );
      expect(failure, isA<AuthorizationFailure>());
    });

    test('not-found maps to NotFoundFailure', () {
      final failure = ErrorMapper.map(
        FirebaseException(plugin: 'cloud_firestore', code: 'not-found'),
      );
      expect(failure, isA<NotFoundFailure>());
    });

    test('already-exists maps to ConflictFailure', () {
      final failure = ErrorMapper.map(
        FirebaseException(plugin: 'cloud_firestore', code: 'already-exists'),
      );
      expect(failure, isA<ConflictFailure>());
    });

    test('deadline-exceeded maps to TimeoutFailure', () {
      final failure = ErrorMapper.map(
        FirebaseException(plugin: 'cloud_functions', code: 'deadline-exceeded'),
      );
      expect(failure, isA<TimeoutFailure>());
    });

    test('unavailable maps to UnavailableFailure', () {
      final failure = ErrorMapper.map(
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
      );
      expect(failure, isA<UnavailableFailure>());
    });

    test('resource-exhausted maps to UnavailableFailure', () {
      final failure = ErrorMapper.map(
        FirebaseException(
            plugin: 'cloud_firestore', code: 'resource-exhausted'),
      );
      expect(failure, isA<UnavailableFailure>());
    });

    test(
        'an unrecognized code still maps deterministically to '
        'UnexpectedFailure, never crashes', () {
      final failure = ErrorMapper.map(
        FirebaseException(
            plugin: 'firebase_storage', code: 'some-future-unknown-code'),
      );
      expect(failure, isA<UnexpectedFailure>());
    });

    test(
        'the vendor code is preserved in debugMessage, never in the '
        'user-facing message', () {
      final failure = ErrorMapper.map(
        FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
          message: 'Missing or insufficient permissions.',
        ),
      );
      expect(failure.debugMessage, contains('permission-denied'));
      expect(failure.message, isNot(contains('permission-denied')));
    });

    test(
        'applies equally to a firebase_storage-plugin exception (shared '
        'FirebaseException type)', () {
      final failure = ErrorMapper.map(
        FirebaseException(plugin: 'firebase_storage', code: 'not-found'),
      );
      expect(failure, isA<NotFoundFailure>());
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
