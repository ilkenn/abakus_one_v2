/// The application-facing error representation. `Failure` is what
/// repositories/services return or throw upward and what state
/// classes/UI are allowed to hold and display — never a raw exception.
///
/// [message] is always Turkish and safe to show to a user as-is. Any
/// technical detail (the original exception's `toString()`, a vendor
/// error code, etc.) belongs in [debugMessage], which exists for logs
/// and error reports only — no UI ever renders it, and it must never
/// itself contain secrets, tokens, or other sensitive data. Neither field
/// carries a stack trace: that stays with the original exception, which
/// is reported separately (see `docs/architecture_bible.md` §11).
///
/// This is a closed, `switch`-exhaustive hierarchy: every call site
/// that branches on a `Failure` gets an analyzer error if a new subtype
/// is added and left unhandled, rather than silently falling through.
sealed class Failure {
  const Failure({required this.message, this.debugMessage});

  final String message;
  final String? debugMessage;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is Failure &&
            other.message == message &&
            other.debugMessage == debugMessage);
  }

  @override
  int get hashCode => Object.hash(runtimeType, message, debugMessage);

  @override
  String toString() => '$runtimeType(message: $message, '
      'debugMessage: $debugMessage)';
}

/// User input failed validation (a form field, a normalized value, a
/// pre-condition checked before calling a repository/service).
final class ValidationFailure extends Failure {
  const ValidationFailure({required super.message, super.debugMessage});
}

/// The current user isn't signed in, or their session is invalid/expired.
final class AuthenticationFailure extends Failure {
  const AuthenticationFailure({required super.message, super.debugMessage});
}

/// The current user is signed in but isn't allowed to perform the
/// requested action.
final class AuthorizationFailure extends Failure {
  const AuthorizationFailure({required super.message, super.debugMessage});
}

/// No usable network connection, or the request otherwise failed at the
/// connectivity level (before reaching/returning from the server).
final class NetworkFailure extends Failure {
  const NetworkFailure({required super.message, super.debugMessage});
}

/// The operation didn't complete within an acceptable amount of time.
final class TimeoutFailure extends Failure {
  const TimeoutFailure({required super.message, super.debugMessage});
}

/// The requested resource doesn't exist.
final class NotFoundFailure extends Failure {
  const NotFoundFailure({required super.message, super.debugMessage});
}

/// The request conflicts with the current state of the resource (e.g. a
/// duplicate, a stale write, an action attempted too soon after the last
/// one).
final class ConflictFailure extends Failure {
  const ConflictFailure({required super.message, super.debugMessage});
}

/// A dependency (backend, platform capability, third-party service) is
/// reachable but currently unable to serve the request.
final class UnavailableFailure extends Failure {
  const UnavailableFailure({required super.message, super.debugMessage});
}

/// The app or one of its dependencies is misconfigured (a missing/invalid
/// setting, an unsupported environment) in a way the user can't fix by
/// retrying.
final class ConfigurationFailure extends Failure {
  const ConfigurationFailure({required super.message, super.debugMessage});
}

/// Anything that doesn't fit a more specific category above. The
/// deterministic fallback for unrecognized exceptions — see
/// `ErrorMapper`.
final class UnexpectedFailure extends Failure {
  const UnexpectedFailure({required super.message, super.debugMessage});
}
