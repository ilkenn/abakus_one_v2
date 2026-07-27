import 'package:firebase_app_check/firebase_app_check.dart'
    as firebase_app_check;
import 'package:flutter/foundation.dart';

import '../../errors/error_mapper.dart';
import '../logging/log_level.dart';
import '../logging/logging_service.dart';
import 'app_check_service.dart';

/// Matches [firebase_app_check.FirebaseAppCheck.activate]'s signature,
/// narrowed to the modern (non-deprecated) provider parameters. Injected
/// so tests can substitute a fake and assert which provider
/// [FirebaseAppCheckService] selected — the real Firebase SDK isn't
/// available under `flutter test`, same rationale as
/// `FirebaseBootstrapService`'s `FirebaseInitializer` typedef.
typedef AppCheckActivator = Future<void> Function({
  firebase_app_check.AndroidAppCheckProvider? providerAndroid,
  firebase_app_check.AppleAppCheckProvider? providerApple,
  firebase_app_check.WebProvider? providerWeb,
  firebase_app_check.WindowsAppCheckProvider? providerWindows,
});

Future<void> _defaultAppCheckActivator({
  firebase_app_check.AndroidAppCheckProvider? providerAndroid,
  firebase_app_check.AppleAppCheckProvider? providerApple,
  firebase_app_check.WebProvider? providerWeb,
  firebase_app_check.WindowsAppCheckProvider? providerWindows,
}) {
  return firebase_app_check.FirebaseAppCheck.instance.activate(
    providerAndroid: providerAndroid ??
        const firebase_app_check.AndroidPlayIntegrityProvider(),
    providerApple:
        providerApple ?? const firebase_app_check.AppleDeviceCheckProvider(),
    providerWeb: providerWeb,
    providerWindows:
        providerWindows ?? const firebase_app_check.WindowsDebugProvider(),
  );
}

/// The real, Firebase-backed [AppCheckService].
///
/// Provider policy (approved architecture decision, Phase 2 Sprint 2):
/// - **Android**: Play Integrity in staging/production; the debug
///   provider only in [AppEnvironment.development].
/// - **iOS/macOS**: App Attest with DeviceCheck fallback in staging/
///   production; the debug provider only in development.
/// - **Web**: reCAPTCHA Enterprise, but only once
///   [webRecaptchaEnterpriseSiteKey] is actually supplied — no site key is
///   hardcoded here (it isn't a secret, but it also isn't provisioned
///   yet), so Web App Check stays unactivated (logged, not thrown) until
///   one is. This is the "prepare for reCAPTCHA Enterprise integration"
///   the sprint asked for: the integration point exists, activation
///   doesn't yet.
/// - **Windows**: this version of `firebase_app_check` supports *only* the
///   debug provider on Windows — there is no Play-Integrity/DeviceCheck
///   equivalent for the desktop C++ SDK. Activating it in staging/
///   production would mean silently running a debug provider there,
///   which [AppCheckService]'s contract forbids — so Windows only
///   activates App Check in development; staging/production leave it
///   unactivated (logged) rather than fake a production posture that
///   doesn't exist for this platform.
/// - **Linux/Fuchsia**: unsupported by `firebase_app_check` — intentional
///   no-op (logged), matching how `FirebaseOptionsSelector`/Firebase
///   itself already treats Linux as having no Firebase app registration.
///
/// Which provider gets selected is decided entirely inside [initialize] by
/// [allowsDebugTooling] (see `AppEnvironmentConfig.allowsDebugTooling`,
/// `true` only for [AppEnvironment.development]) — no caller-supplied
/// parameter can request a debug provider, so a debug provider being used
/// in production isn't just discouraged, there is no code path that
/// produces it.
class FirebaseAppCheckService implements AppCheckService {
  FirebaseAppCheckService({
    required bool allowsDebugTooling,
    required LoggingService loggingService,
    String? webRecaptchaEnterpriseSiteKey,
    AppCheckActivator? activate,
  })  : _allowsDebugTooling = allowsDebugTooling,
        _loggingService = loggingService,
        _webRecaptchaEnterpriseSiteKey = webRecaptchaEnterpriseSiteKey,
        _activate = activate ?? _defaultAppCheckActivator;

  final bool _allowsDebugTooling;
  final LoggingService _loggingService;
  final String? _webRecaptchaEnterpriseSiteKey;
  final AppCheckActivator _activate;

  @override
  Future<void> initialize() async {
    try {
      if (kIsWeb) {
        await _activateWeb();
        return;
      }
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          await _activate(
            providerAndroid: _allowsDebugTooling
                ? const firebase_app_check.AndroidDebugProvider()
                : const firebase_app_check.AndroidPlayIntegrityProvider(),
          );
          return;
        case TargetPlatform.iOS:
        case TargetPlatform.macOS:
          await _activate(
            providerApple: _allowsDebugTooling
                ? const firebase_app_check.AppleDebugProvider()
                : const firebase_app_check
                    .AppleAppAttestWithDeviceCheckFallbackProvider(),
          );
          return;
        case TargetPlatform.windows:
          if (_allowsDebugTooling) {
            await _activate(
              providerWindows: const firebase_app_check.WindowsDebugProvider(),
            );
          } else {
            _logInfo(
              'App Check: Windows has no non-debug provider in this '
              'firebase_app_check version — not activated outside '
              'development.',
            );
          }
          return;
        case TargetPlatform.linux:
        case TargetPlatform.fuchsia:
          _logInfo(
            'App Check: platform not supported by firebase_app_check — '
            'running without App Check.',
          );
          return;
      }
    } catch (error, stackTrace) {
      final failure = ErrorMapper.map(error);
      _loggingService.log(
        LogLevel.error,
        'App Check initialization failed: ${failure.message}',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _activateWeb() async {
    final siteKey = _webRecaptchaEnterpriseSiteKey;
    if (siteKey == null) {
      _logInfo(
        'App Check: no reCAPTCHA Enterprise site key configured yet — '
        'Web App Check not activated.',
      );
      return;
    }
    await _activate(
      providerWeb: firebase_app_check.ReCaptchaEnterpriseProvider(siteKey),
    );
  }

  void _logInfo(String message) {
    _loggingService.log(LogLevel.info, message);
  }
}
