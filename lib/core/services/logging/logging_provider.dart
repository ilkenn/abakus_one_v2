import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'console_logging_service.dart';
import 'logging_service.dart';
import 'noop_logging_service.dart';

/// [ConsoleLoggingService] for a debug/profile build, [NoOpLoggingService]
/// for a release build, mirroring the [kReleaseMode] gating already used
/// for `features/auth/presentation/providers/auth_provider.dart`'s
/// `authRepositoryProvider`: nothing here should ever print application
/// state to an end user's release-build console.
///
/// Extracted as a plain function (not just a provider body) so
/// pre-`ProviderScope` code — `main()`'s Firebase bootstrap runs before the
/// provider tree exists — can select the same instance [loggingServiceProvider]
/// would, without duplicating the [kReleaseMode] check in two places.
LoggingService defaultLoggingService() {
  if (kReleaseMode) {
    return const NoOpLoggingService();
  }
  return const ConsoleLoggingService();
}

/// The [LoggingService] currently in use — see [defaultLoggingService].
final loggingServiceProvider = Provider<LoggingService>((ref) {
  return defaultLoggingService();
});
