import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/app_check/app_check_provider.dart';
import '../core/services/app_check/app_check_service.dart';
import '../core/services/crash_reporting/crash_reporting_provider.dart';
import '../core/services/crash_reporting/crash_reporting_service.dart';
import '../core/services/feature_flags/feature_flags_provider.dart';
import '../core/services/feature_flags/feature_flags_service.dart';
import '../core/services/logging/logging_provider.dart';
import '../core/services/logging/logging_service.dart';
import '../core/services/remote_config/remote_config_provider.dart';
import '../core/services/remote_config/remote_config_service.dart';
import '../features/auth/presentation/providers/auth_provider.dart';
import 'firebase_bootstrap_service.dart';
import 'firebase_ready_provider.dart';

/// The already-initialized services [bootstrapApp] produced, ready to be
/// installed as [ProviderScope] overrides — so `main()` never constructs a
/// service directly, only passes along what [bootstrapApp] already built.
class AppBootstrapResult {
  const AppBootstrapResult({
    required this.isFirebaseReady,
    required this.loggingService,
    required this.featureFlagsService,
    required this.remoteConfigService,
    required this.appCheckService,
    required this.crashReportingService,
    required this.resolvedAuthState,
  });

  final bool isFirebaseReady;
  final LoggingService loggingService;
  final FeatureFlagsService featureFlagsService;
  final RemoteConfigService remoteConfigService;
  final AppCheckService appCheckService;
  final CrashReportingService crashReportingService;

  /// The result of resolving any persisted session — see [bootstrapApp]'s
  /// own doc comment, step 4. Startup routing cleanup (splash removal):
  /// this used to be resolved later, inside `SplashScreen.initState()`,
  /// after the first Flutter frame had already rendered. Resolving it here
  /// instead means the very first frame `runApp()` ever produces can
  /// already be the correct destination screen.
  final AuthState resolvedAuthState;

  /// The [ProviderScope] overrides that make the running app use exactly
  /// the service instances this bootstrap already initialized, instead of
  /// each provider constructing its own (which would mean initializing
  /// Remote Config/App Check a second time, redundantly, on first read).
  List<Override> get providerOverrides => [
        firebaseReadyProvider.overrideWithValue(isFirebaseReady),
        loggingServiceProvider.overrideWithValue(loggingService),
        featureFlagsServiceProvider.overrideWithValue(featureFlagsService),
        remoteConfigServiceProvider.overrideWithValue(remoteConfigService),
        appCheckServiceProvider.overrideWithValue(appCheckService),
        crashReportingServiceProvider.overrideWithValue(crashReportingService),
        authProvider.overrideWith(() => SeededAuthNotifier(resolvedAuthState)),
      ];
}

/// The application's single runtime bootstrap sequence — everything that
/// must happen before [runApp], in order:
///
/// 1. [WidgetsFlutterBinding.ensureInitialized] — required before any
///    platform channel use, including Firebase's.
/// 2. [FirebaseBootstrapService.initialize] — never throws; `main()` boots
///    either way (see its own doc comment).
/// 3. Resolve [FeatureFlagsService]/[RemoteConfigService]/[AppCheckService]
///    for [isFirebaseReady] (via a short-lived [ProviderContainer], so
///    this reuses the exact same provider wiring the running app will use
///    — not a second, parallel construction path) and initialize each.
///    Feature flags and Remote Config share one `initialize()` call
///    ([RemoteConfigFeatureFlagsService.initialize] delegates to the
///    underlying [RemoteConfigService]); App Check is independent, so both
///    run concurrently. Neither implementation throws — a fetch failure,
///    a disabled API, or no network all leave safe defaults in place
///    rather than blocking startup, per Sprint 2's explicit requirement.
/// 4. [AuthNotifier.checkPersistedSession] — resolved concurrently with
///    step 3 in the same container. Startup routing cleanup (splash
///    removal): this used to run later, inside `SplashScreen.initState()`,
///    after the first Flutter frame had already rendered — the router
///    would show Splash regardless, then redirect once this resolved.
///    Running it here instead means [appRouterProvider]'s
///    `initialLocation` can already read a fully-resolved [AuthState] the
///    moment the app's real [ProviderScope] is built, so the very first
///    frame is already the correct destination. Never throws (see
///    [AuthNotifier.checkPersistedSession]'s own doc comment) — a broken
///    session resolves to "not signed in," not a hang or a crash.
///
/// This function contains no feature-specific or business logic — it only
/// sequences already-tested services' own `initialize()`/session-check
/// contracts.
Future<AppBootstrapResult> bootstrapApp() async {
  WidgetsFlutterBinding.ensureInitialized();

  // AP-3 continuation (`docs/decisions.md` ADR-041) — `cryptography_flutter`
  // (the platform-accelerated Ed25519 backend `DeviceKeyStore` benefits
  // from, Android Keystore/iOS Keychain-backed where available, behind the
  // exact same `package:cryptography` API) is auto-registered by Flutter
  // itself in this package version — no explicit enable call is needed or
  // available (`FlutterCryptography.enable()` is deprecated as a no-op).
  // This never changes what trust tier a device resolves to (still
  // PLATFORM_PROTECTED, never HARDWARE_ATTESTED — see that ADR).

  final loggingService = defaultLoggingService();
  final isFirebaseReady = await FirebaseBootstrapService(
    loggingService: loggingService,
  ).initialize();

  final container = ProviderContainer(
    overrides: [
      firebaseReadyProvider.overrideWithValue(isFirebaseReady),
      loggingServiceProvider.overrideWithValue(loggingService),
    ],
  );

  final featureFlagsService = container.read(featureFlagsServiceProvider);
  final remoteConfigService = container.read(remoteConfigServiceProvider);
  final appCheckService = container.read(appCheckServiceProvider);
  final crashReportingService = container.read(crashReportingServiceProvider);
  final authNotifier = container.read(authProvider.notifier);

  await Future.wait([
    featureFlagsService.initialize(),
    appCheckService.initialize(),
    crashReportingService.initialize(),
    authNotifier.checkPersistedSession(),
  ]);

  final resolvedAuthState = container.read(authProvider);

  container.dispose();

  return AppBootstrapResult(
    isFirebaseReady: isFirebaseReady,
    loggingService: loggingService,
    featureFlagsService: featureFlagsService,
    remoteConfigService: remoteConfigService,
    crashReportingService: crashReportingService,
    appCheckService: appCheckService,
    resolvedAuthState: resolvedAuthState,
  );
}
