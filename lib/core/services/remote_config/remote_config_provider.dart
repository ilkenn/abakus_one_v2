import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../bootstrap/firebase_ready_provider.dart';
import '../../config/app_environment_config_provider.dart';
import '../logging/logging_provider.dart';
import 'firebase_remote_config_service.dart';
import 'noop_remote_config_service.dart';
import 'remote_config_service.dart';

/// The application-wide [RemoteConfigService].
///
/// Resolves to [FirebaseRemoteConfigService] once Firebase has actually
/// initialized successfully ([firebaseReadyProvider]); falls back to
/// [NoOpRemoteConfigService] otherwise — including every `flutter test`
/// run, where no real Firebase app exists, and any environment where
/// [FirebaseBootstrapService] itself failed. This mirrors
/// `FirebaseAuthRepository`'s not-yet-built equivalent guard and keeps
/// "Firebase isn't ready" a single, fail-closed condition rather than
/// something every call site re-checks.
final remoteConfigServiceProvider = Provider<RemoteConfigService>((ref) {
  final isFirebaseReady = ref.watch(firebaseReadyProvider);
  if (!isFirebaseReady) {
    return const NoOpRemoteConfigService();
  }
  return FirebaseRemoteConfigService(
    environment: ref.watch(appEnvironmentConfigProvider).environment,
    loggingService: ref.watch(loggingServiceProvider),
  );
});
