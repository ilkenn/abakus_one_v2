import 'log_level.dart';

/// The application's **structured application logging** boundary — a
/// leveled, contextual log line, distinct from [CrashReportingService]
/// (`core/services/crash_reporting/`), which exists specifically for
/// exception/crash *reporting* to a future backend, not general-purpose
/// messages. Keeping them separate means a routine debug line and an
/// actual reportable failure are never forced through the same API.
///
/// [log] is synchronous and local-only by design: unlike crash reporting,
/// nothing here talks to a network or a vendor SDK, so there's no async
/// boundary to expose. A call to [log] must never throw — an
/// implementation that also can't guarantee that isn't safe to install.
///
/// [context] values are redacted (see `log_redactor.dart`) by
/// implementations before they reach any sink, matched by *key name*
/// only (`token`, `password`, `otp`, `phone`, ...). [message] and [error]
/// are plain text and are **not** scanned for sensitive content — per
/// `docs/architecture_bible.md` §11 ("no tokens/phone numbers/personal
/// data in logs"), callers must never interpolate a secret, OTP value,
/// token, or personal-data value directly into [message]; put it in
/// [context] instead, where it can actually be redacted.
abstract interface class LoggingService {
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  });
}
