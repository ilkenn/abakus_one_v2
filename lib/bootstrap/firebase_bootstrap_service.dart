import 'package:firebase_core/firebase_core.dart';

import '../core/config/firebase_options_selector.dart';
import '../core/errors/error_mapper.dart';
import '../core/services/logging/log_level.dart';
import '../core/services/logging/logging_service.dart';
import 'app_environment.dart';

/// Matches [Firebase.initializeApp]'s signature, narrowed to the part this
/// service actually needs (nothing here uses the returned [FirebaseApp]).
/// Injected so tests can substitute a fake — the real Firebase SDK isn't
/// available under `flutter test`.
typedef FirebaseInitializer = Future<void> Function({FirebaseOptions? options});

Future<void> _defaultFirebaseInitializer({FirebaseOptions? options}) async {
  await Firebase.initializeApp(options: options);
}

/// Initializes Firebase for [AppEnvironment.current], safely: any failure
/// is caught, mapped through [ErrorMapper], and logged via [LoggingService]
/// — never left as an unhandled exception, and never exposed to the user
/// (only [Failure.message] — a generic, Turkish, user-safe string — and the
/// raw `error`/`stackTrace`, which [LoggingService] implementations redact
/// before printing, ever reach the log; no [FirebaseOptions], API key, or
/// other credential is logged).
///
/// Called once, from `main()`, before `runApp`. [initialize] never throws —
/// its `bool` result says whether Firebase is usable, and the app boots
/// either way (see `main.dart`'s `firebaseReadyProvider` override): guest/
/// menu browsing never depended on Firebase and is unaffected by either
/// outcome; authentication-dependent functionality (Sprint 4+) is expected
/// to check `firebaseReadyProvider` and stay unavailable when this returns
/// `false`, the same fail-closed shape `ProductionUnavailableAuthRepository`
/// already established for "no backend available."
class FirebaseBootstrapService {
  FirebaseBootstrapService({
    required LoggingService loggingService,
    FirebaseInitializer? initializeApp,
  })  : _loggingService = loggingService,
        _initializeApp = initializeApp ?? _defaultFirebaseInitializer;

  final LoggingService _loggingService;
  final FirebaseInitializer _initializeApp;

  Future<bool> initialize() async {
    try {
      await _initializeApp(
        options: FirebaseOptionsSelector.forEnvironment(AppEnvironment.current),
      );
      return true;
    } catch (error, stackTrace) {
      final failure = ErrorMapper.map(error);
      _loggingService.log(
        LogLevel.error,
        'Firebase initialization failed: ${failure.message}',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }
}
