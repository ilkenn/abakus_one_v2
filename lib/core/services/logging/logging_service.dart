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
/// Every field an implementation actually prints is sanitized first (see
/// `log_redactor.dart`): [context] by key name (`token`, `password`,
/// `otp`, `phone`, ...), [message] and [error]'s text by a small set of
/// recognizable patterns (bearer/labeled tokens, emails, long digit runs
/// that look like phone/card numbers). Pattern-based text redaction is
/// necessarily incomplete — it catches recognizable *shapes*, not
/// arbitrary sensitive meaning — so per `docs/architecture_bible.md` §11
/// ("no tokens/phone numbers/personal data in logs"), callers should
/// still prefer passing a sensitive value via [context] over
/// interpolating it into [message] wherever practical; [context]'s
/// key-based redaction is the more reliable of the two.
abstract interface class LoggingService {
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  });
}
