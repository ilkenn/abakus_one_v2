import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'console_logging_service.dart';
import 'logging_service.dart';
import 'noop_logging_service.dart';

/// The [LoggingService] currently in use — [ConsoleLoggingService] for a
/// debug/profile build, [NoOpLoggingService] for a release build, mirroring
/// the [kReleaseMode] gating already used for
/// `features/auth/presentation/providers/auth_provider.dart`'s
/// `authRepositoryProvider`: nothing here should ever print application
/// state to an end user's release-build console.
final loggingServiceProvider = Provider<LoggingService>((ref) {
  if (kReleaseMode) {
    return const NoOpLoggingService();
  }
  return const ConsoleLoggingService();
});
