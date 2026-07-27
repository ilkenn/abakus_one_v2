import 'dart:async';

import 'package:flutter/services.dart';

import 'failure.dart';

/// Converts a raw, thrown [Object] (a framework/platform exception, a
/// malformed value, anything else a lower layer might throw) into the
/// application-facing [Failure] type. This is the one place that
/// vendor/platform exception types are inspected — nothing above this
/// boundary (domain, presentation) should ever import or branch on them
/// directly (see `docs/architecture_bible.md` §11).
///
/// [map] is deliberately scoped to exception types that are safe to
/// reference from a platform-agnostic `core/` file:
/// - `dart:async`'s [TimeoutException] and `dart:core`'s [FormatException]
///   are available on every Flutter target, including web.
/// - [PlatformException] comes from `package:flutter/services.dart` (the
///   Flutter framework itself, not a vendor plugin), so it's safe to
///   depend on here too.
/// - Connectivity failures (`SocketException`, `HttpException`, ...) live
///   in `dart:io`, which does **not** compile on web — importing it here
///   would break `flutter build web` for every caller of this file, not
///   just network code. [_isConnectivityError] recognizes them by
///   runtime-type name instead, so this stays platform-agnostic without
///   pulling in `dart:io` or a networking package this app doesn't have
///   yet.
///
/// This mapper intentionally does **not** know about any feature-specific
/// exception (e.g. auth's `AuthCooldownActiveException`): `core/` is
/// forbidden from importing `features/` (see `CLAUDE.md` §3). A feature
/// that wants `Failure`-typed errors maps its own exceptions locally,
/// constructing the `Failure` subtypes from `failure.dart` directly.
///
/// Every branch is deterministic and total — an exception type this
/// mapper doesn't recognize always becomes [UnexpectedFailure], never an
/// unhandled error. [map] never throws, logs, or reports anything itself;
/// it has no dependencies and takes no `BuildContext`. Preserving the
/// original exception/stack trace for logging is the caller's job — nothing
/// this function returns carries either (see `Failure`'s own doc comment).
abstract final class ErrorMapper {
  ErrorMapper._();

  static Failure map(Object error) {
    return switch (error) {
      TimeoutException() => TimeoutFailure(
          message: 'İşlem zaman aşımına uğradı. Lütfen tekrar deneyin.',
          debugMessage: error.toString(),
        ),
      FormatException() => ValidationFailure(
          message: 'Girdiğiniz bilgileri kontrol edin.',
          debugMessage: error.toString(),
        ),
      PlatformException() => UnexpectedFailure(
          message: 'Beklenmeyen bir hata oluştu.',
          debugMessage: 'PlatformException(${error.code}): ${error.message}',
        ),
      _ when _isConnectivityError(error) => NetworkFailure(
          message: 'İnternet bağlantınızı kontrol edin.',
          debugMessage: error.toString(),
        ),
      _ => UnexpectedFailure(
          message: 'Beklenmeyen bir hata oluştu.',
          debugMessage: error.toString(),
        ),
    };
  }

  static bool _isConnectivityError(Object error) {
    return const {
      'SocketException',
      'HttpException',
      'WebSocketException',
      'ClientException',
    }.contains(error.runtimeType.toString());
  }
}
