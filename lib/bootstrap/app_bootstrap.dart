import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/app_check/app_check_provider.dart';
import '../core/services/app_check/app_check_service.dart';
import '../core/services/feature_flags/feature_flags_provider.dart';
import '../core/services/feature_flags/feature_flags_service.dart';
import '../core/services/logging/logging_provider.dart';
import '../core/services/logging/logging_service.dart';
import '../core/services/remote_config/remote_config_provider.dart';
import '../core/services/remote_config/remote_config_service.dart';
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
  });

  final bool isFirebaseReady;
  final LoggingService loggingService;
  final FeatureFlagsService featureFlagsService;
  final RemoteConfigService remoteConfigService;
  final AppCheckService appCheckService;

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
///
/// This function contains no feature-specific or business logic — it only
/// sequences already-tested services' own `initialize()` contracts.
Future<AppBootstrapResult> bootstrapApp() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  await Future.wait([
    featureFlagsService.initialize(),
    appCheckService.initialize(),
  ]);

  container.dispose();

  return AppBootstrapResult(
    isFirebaseReady: isFirebaseReady,
    loggingService: loggingService,
    featureFlagsService: featureFlagsService,
    remoteConfigService: remoteConfigService,
    appCheckService: appCheckService,
  );
}
