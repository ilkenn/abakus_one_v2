import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../bootstrap/firebase_ready_provider.dart';
import '../../config/app_environment_config_provider.dart';
import '../logging/logging_provider.dart';
import 'app_check_service.dart';
import 'firebase_app_check_service.dart';
import 'noop_app_check_service.dart';

/// The application-wide [AppCheckService].
///
/// Resolves to [FirebaseAppCheckService] once Firebase has actually
/// initialized successfully ([firebaseReadyProvider]); falls back to
/// [NoOpAppCheckService] otherwise — including every `flutter test` run,
/// where no real Firebase app exists. No reCAPTCHA Enterprise site key is
/// configured yet (see `FirebaseAppCheckService`'s doc comment), so Web
/// App Check stays unactivated until one is provisioned and wired here.
final appCheckServiceProvider = Provider<AppCheckService>((ref) {
  final isFirebaseReady = ref.watch(firebaseReadyProvider);
  if (!isFirebaseReady) {
    return const NoOpAppCheckService();
  }
  return FirebaseAppCheckService(
    allowsDebugTooling:
        ref.watch(appEnvironmentConfigProvider).allowsDebugTooling,
    loggingService: ref.watch(loggingServiceProvider),
  );
});
