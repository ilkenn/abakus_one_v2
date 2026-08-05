import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../../errors/error_mapper.dart';
import '../logging/log_level.dart';
import '../logging/log_redactor.dart';
import '../logging/logging_service.dart';
import 'crash_reporting_service.dart';

/// Matches the subset of [FirebaseCrashlytics.instance]'s API this service
/// actually calls — injected so tests can substitute a fake, the same
/// rationale `FirebaseBootstrapService`/`FirebaseAppCheckService` already
/// use (the real Crashlytics SDK isn't available under `flutter test`).
abstract interface class CrashlyticsClient {
  Future<void> recordError(
    dynamic exception,
    StackTrace? stack, {
    dynamic reason,
    Iterable<Object> information,
    bool? fatal,
    bool printDetails,
  });

  Future<void> recordFlutterError(FlutterErrorDetails details, {bool? fatal});

  Future<void> log(String message);

  Future<void> setUserIdentifier(String identifier);

  Future<void> setCustomKey(String key, Object value);

  Future<void> setCrashlyticsCollectionEnabled(bool enabled);
}

class _DefaultCrashlyticsClient implements CrashlyticsClient {
  const _DefaultCrashlyticsClient();

  FirebaseCrashlytics get _instance => FirebaseCrashlytics.instance;

  @override
  Future<void> recordError(
    dynamic exception,
    StackTrace? stack, {
    dynamic reason,
    Iterable<Object> information = const [],
    bool? fatal,
    bool printDetails = true,
  }) {
    return _instance.recordError(
      exception,
      stack,
      reason: reason,
      information: information,
      fatal: fatal ?? false,
      printDetails: printDetails,
    );
  }

  @override
  Future<void> recordFlutterError(FlutterErrorDetails details, {bool? fatal}) {
    return _instance.recordFlutterError(details, fatal: fatal ?? false);
  }

  @override
  Future<void> log(String message) => _instance.log(message);

  @override
  Future<void> setUserIdentifier(String identifier) =>
      _instance.setUserIdentifier(identifier);

  @override
  Future<void> setCustomKey(String key, Object value) =>
      _instance.setCustomKey(key, value);

  @override
  Future<void> setCrashlyticsCollectionEnabled(bool enabled) =>
      _instance.setCrashlyticsCollectionEnabled(enabled);
}

/// The real, Firebase Crashlytics-backed [CrashReportingService] — Phase 9
/// (`docs/decisions.md` ADR-026). Closes the Release Readiness
/// `crashReporting: notReady` gap Phase 8 self-identified
/// (`BuildReleaseReadinessSnapshot`).
///
/// **Web is not supported** — `firebase_crashlytics` has no web
/// implementation (confirmed against the package's own platform support).
/// [FirebaseCrashlyticsService] on web behaves as a documented no-op
/// (logged once via [initialize], not per call) rather than throwing on
/// every method — the same "platform genuinely unsupported, log once,
/// never crash the caller" pattern `FirebaseAppCheckService` already
/// established for Linux/Fuchsia.
///
/// [allowsDebugTooling] (`true` only for [AppEnvironment.development] —
/// see `AppEnvironmentConfig`) gates collection itself: development
/// crashes never reach the real Crashlytics dashboard, so it isn't
/// polluted with local debugging noise, mirroring
/// `FirebaseAppCheckService`'s own environment-aware provider selection.
///
/// Every method catches and swallows its own errors — a crash-reporting
/// call must never itself become the reason the app crashes.
class FirebaseCrashlyticsService implements CrashReportingService {
  FirebaseCrashlyticsService({
    required bool allowsDebugTooling,
    required LoggingService loggingService,
    CrashlyticsClient? client,
  })  : _allowsDebugTooling = allowsDebugTooling,
        _loggingService = loggingService,
        _client = client ?? const _DefaultCrashlyticsClient();

  final bool _allowsDebugTooling;
  final LoggingService _loggingService;
  final CrashlyticsClient _client;

  bool get _isSupported => !kIsWeb;

  @override
  Future<void> initialize() async {
    if (!_isSupported) {
      _loggingService.log(
        LogLevel.info,
        'Crashlytics: web has no firebase_crashlytics implementation — '
        'running without crash reporting.',
      );
      return;
    }
    try {
      // Never collect in development — real crash data must never be
      // polluted with local debugging noise.
      await _client.setCrashlyticsCollectionEnabled(!_allowsDebugTooling);
    } catch (error, stackTrace) {
      final failure = ErrorMapper.map(error);
      _loggingService.log(
        LogLevel.error,
        'Crashlytics initialization failed: ${failure.message}',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> recordError(
    Object error, {
    StackTrace? stackTrace,
    String? reason,
    bool fatal = false,
    Map<String, Object?>? context,
  }) async {
    if (!_isSupported) return;
    try {
      // Crashlytics is a third-party vendor once real data flows through
      // it — the same redaction discipline `LoggingService` already
      // applies to console/local logs must apply here too, never assume
      // a "trusted" destination is exempt.
      final redactedContext =
          context == null ? null : LogRedactor.redactContext(context);
      await _client.recordError(
        error,
        stackTrace,
        reason: reason == null ? null : LogRedactor.sanitizeText(reason),
        information: redactedContext == null
            ? const []
            : [
                redactedContext.entries
                    .map((e) => '${e.key}=${e.value}')
                    .join(', ')
              ],
        fatal: fatal,
      );
    } catch (_) {
      // A crash-reporting failure must never itself crash the caller.
    }
  }

  @override
  Future<void> recordFlutterError(
    FlutterErrorDetails details, {
    bool fatal = false,
  }) async {
    if (!_isSupported) return;
    try {
      await _client.recordFlutterError(details, fatal: fatal);
    } catch (_) {}
  }

  @override
  Future<void> log(String message) async {
    if (!_isSupported) return;
    try {
      await _client.log(LogRedactor.sanitizeText(message));
    } catch (_) {}
  }

  @override
  Future<void> setUserIdentifier(String identifier) async {
    if (!_isSupported) return;
    try {
      await _client.setUserIdentifier(identifier);
    } catch (_) {}
  }

  @override
  Future<void> setCustomKey(String key, Object value) async {
    if (!_isSupported) return;
    try {
      // Reuses `redactContext`'s exact key-marker check via a one-entry
      // map, rather than re-implementing the marker list here.
      final redactedValue = LogRedactor.redactContext({key: value})[key];
      await _client.setCustomKey(key, redactedValue ?? value);
    } catch (_) {}
  }
}
