import 'dart:async';

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
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
/// - [FirebaseException] (`package:firebase_core`, Phase 9 —
///   `docs/decisions.md` ADR-026) is a real, always-present, web-safe
///   dependency of this app (unlike `dart:io`, see below) — every other
///   Firebase product package this app uses
///   (`firebase_auth`/`cloud_firestore`/`firebase_storage`/
///   `cloud_functions`) throws either this exact type or a subclass of it
///   (`FirebaseAuthException extends FirebaseException`), so one `is`
///   check here covers all of them, including a subclass — matching by
///   `runtimeType` name (as [_isConnectivityError] does for `dart:io`
///   below) would silently miss any subclass, which is exactly the trap
///   a first draft of this mapper fell into.
/// - Connectivity failures (`SocketException`, `HttpException`, ...) live
///   in `dart:io`, which does **not** compile on web — importing it here
///   would break `flutter build web` for every caller of this file, not
///   just network code. [_isConnectivityError] recognizes them by
///   runtime-type name instead, so this stays platform-agnostic without
///   pulling in `dart:io` or a networking package this app doesn't have.
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
/// it takes no `BuildContext`. Preserving the original exception/stack
/// trace for logging is the caller's job — nothing this function returns
/// carries either (see `Failure`'s own doc comment).
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
      // `plugin == 'firebase_auth'` distinguishes a real
      // `FirebaseAuthException` (or any subclass of it) from every other
      // Firebase product's `FirebaseException` without needing to import
      // `firebase_auth` itself just for this one check.
      FirebaseException(plugin: 'firebase_auth') =>
        _mapFirebaseAuthError(error),
      FirebaseException() => _mapFirestoreLikeError(error),
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

  static Failure _mapFirebaseAuthError(FirebaseException error) {
    final String debugMessage =
        'FirebaseAuthException(${error.code}): ${error.message}';
    return switch (error.code) {
      'invalid-verification-code' ||
      'invalid-verification-id' ||
      'invalid-phone-number' =>
        ValidationFailure(
          message: 'Girdiğiniz kod veya telefon numarası geçersiz.',
          debugMessage: debugMessage,
        ),
      'too-many-requests' => UnavailableFailure(
          message: 'Çok fazla deneme yapıldı. Lütfen daha sonra tekrar '
              'deneyin.',
          debugMessage: debugMessage,
        ),
      'user-disabled' => AuthorizationFailure(
          message: 'Hesabınız devre dışı bırakılmış.',
          debugMessage: debugMessage,
        ),
      'session-expired' ||
      'user-token-expired' ||
      'requires-recent-login' ||
      'user-not-found' =>
        AuthenticationFailure(
          message: 'Oturumunuz sona erdi. Lütfen tekrar giriş yapın.',
          debugMessage: debugMessage,
        ),
      'network-request-failed' => NetworkFailure(
          message: 'İnternet bağlantınızı kontrol edin.',
          debugMessage: debugMessage,
        ),
      _ => AuthenticationFailure(
          message: 'Kimlik doğrulama sırasında bir hata oluştu.',
          debugMessage: debugMessage,
        ),
    };
  }

  /// Covers `cloud_firestore`, `firebase_storage`, and `cloud_functions`
  /// alike — all three throw the same [FirebaseException] type with the
  /// same well-known `code` vocabulary (`permission-denied`, `not-found`,
  /// `unavailable`, ...), so one mapping serves all three.
  static Failure _mapFirestoreLikeError(FirebaseException error) {
    final String debugMessage = 'FirebaseException(${error.code}): '
        '${error.message}';
    return switch (error.code) {
      'permission-denied' || 'unauthenticated' => AuthorizationFailure(
          message: 'Bu işlem için yetkiniz yok.',
          debugMessage: debugMessage,
        ),
      'not-found' => NotFoundFailure(
          message: 'İstenen kayıt bulunamadı.',
          debugMessage: debugMessage,
        ),
      'already-exists' || 'aborted' || 'failed-precondition' => ConflictFailure(
          message: 'Bu işlem, kaydın güncel durumuyla çakışıyor. Lütfen '
              'tekrar deneyin.',
          debugMessage: debugMessage,
        ),
      'deadline-exceeded' => TimeoutFailure(
          message: 'İşlem zaman aşımına uğradı. Lütfen tekrar deneyin.',
          debugMessage: debugMessage,
        ),
      'unavailable' || 'resource-exhausted' || 'internal' => UnavailableFailure(
          message: 'Sunucuya şu anda ulaşılamıyor. Lütfen daha sonra '
              'tekrar deneyin.',
          debugMessage: debugMessage,
        ),
      _ => UnexpectedFailure(
          message: 'Beklenmeyen bir hata oluştu.',
          debugMessage: debugMessage,
        ),
    };
  }
}
