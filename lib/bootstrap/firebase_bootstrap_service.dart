import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../core/config/firebase_options_selector.dart';
import '../core/errors/error_mapper.dart';
import '../core/services/logging/log_level.dart';
import '../core/services/logging/logging_service.dart';
import 'app_environment.dart';
import 'firebase_auth_emulator_config.dart';
import 'firebase_firestore_emulator_config.dart';
import 'firebase_functions_emulator_config.dart';
import 'firebase_storage_emulator_config.dart';

/// Matches [Firebase.initializeApp]'s signature, narrowed to the part this
/// service actually needs (nothing here uses the returned [FirebaseApp]).
/// Injected so tests can substitute a fake — the real Firebase SDK isn't
/// available under `flutter test`.
typedef FirebaseInitializer = Future<void> Function({FirebaseOptions? options});

Future<void> _defaultFirebaseInitializer({FirebaseOptions? options}) async {
  await Firebase.initializeApp(options: options);
}

/// Matches [FirebaseAuth.useAuthEmulator]'s signature. Injected for the same
/// testability reason as [FirebaseInitializer] — real `firebase_auth` isn't
/// available under `flutter test`.
typedef AuthEmulatorConnector = void Function(String host, int port);

/// `automaticHostMapping: false` on every one of the four default
/// connectors below is load-bearing, not decorative — see
/// `firebase_core`'s `getMappedHost`/each plugin's own local copy of the
/// same logic (`package:firebase_auth/cloud_firestore/firebase_storage/
/// cloud_functions`'s `use*Emulator` methods): by default (`true`), every
/// FlutterFire plugin unconditionally rewrites the literal strings
/// `'localhost'` and `'127.0.0.1'` to `'10.0.2.2'` on Android — physical
/// device or emulator, no distinction — which is what silently undid the
/// `FirebaseXEmulatorConfig.host` fix (127.0.0.1 → still became 10.0.2.2,
/// unreachable from a physical device even with `adb reverse`, since
/// `adb reverse` only forwards loopback ports, not the distinct address
/// 10.0.2.2). Passing `automaticHostMapping: false` makes this app's own
/// `FIREBASE_EMULATOR_HOST` dart-define (see each `FirebaseXEmulatorConfig`)
/// the single source of truth for the host actually used — an Android
/// Emulator session still gets `10.0.2.2` correctly, just via an explicit
/// `--dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2` override rather than the
/// plugins' own opaque, non-overridable heuristic.
void _defaultConnectAuthEmulator(String host, int port) {
  FirebaseAuth.instance.useAuthEmulator(
    host,
    port,
    automaticHostMapping: false,
  );
}

/// Matches [FirebaseFirestore.useFirestoreEmulator]'s signature. Injected
/// for the same testability reason as [AuthEmulatorConnector] — real
/// `cloud_firestore` isn't available under `flutter test`. See
/// [_defaultConnectAuthEmulator]'s doc comment for why
/// `automaticHostMapping: false` is required here too.
typedef FirestoreEmulatorConnector = void Function(String host, int port);

void _defaultConnectFirestoreEmulator(String host, int port) {
  FirebaseFirestore.instance.useFirestoreEmulator(
    host,
    port,
    automaticHostMapping: false,
  );
}

/// Matches [FirebaseStorage.useStorageEmulator]'s signature. Injected for
/// the same testability reason as [AuthEmulatorConnector] — real
/// `firebase_storage` isn't available under `flutter test`. See
/// [_defaultConnectAuthEmulator]'s doc comment for why
/// `automaticHostMapping: false` is required here too.
typedef StorageEmulatorConnector = void Function(String host, int port);

void _defaultConnectStorageEmulator(String host, int port) {
  FirebaseStorage.instance.useStorageEmulator(
    host,
    port,
    automaticHostMapping: false,
  );
}

/// Matches [FirebaseFunctions.useFunctionsEmulator]'s signature. Injected
/// for the same testability reason as [AuthEmulatorConnector] — real
/// `cloud_functions` isn't available under `flutter test`. See
/// [_defaultConnectAuthEmulator]'s doc comment for why
/// `automaticHostMapping: false` is required here too.
typedef FunctionsEmulatorConnector = void Function(String host, int port);

void _defaultConnectFunctionsEmulator(String host, int port) {
  FirebaseFunctions.instance.useFunctionsEmulator(
    host,
    port,
    automaticHostMapping: false,
  );
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
    AuthEmulatorConnector? connectAuthEmulator,
    FirestoreEmulatorConnector? connectFirestoreEmulator,
    StorageEmulatorConnector? connectStorageEmulator,
    FunctionsEmulatorConnector? connectFunctionsEmulator,
  })  : _loggingService = loggingService,
        _initializeApp = initializeApp ?? _defaultFirebaseInitializer,
        _connectAuthEmulator =
            connectAuthEmulator ?? _defaultConnectAuthEmulator,
        _connectFirestoreEmulator =
            connectFirestoreEmulator ?? _defaultConnectFirestoreEmulator,
        _connectStorageEmulator =
            connectStorageEmulator ?? _defaultConnectStorageEmulator,
        _connectFunctionsEmulator =
            connectFunctionsEmulator ?? _defaultConnectFunctionsEmulator;

  final LoggingService _loggingService;
  final FirebaseInitializer _initializeApp;
  final AuthEmulatorConnector _connectAuthEmulator;
  final FirestoreEmulatorConnector _connectFirestoreEmulator;
  final StorageEmulatorConnector _connectStorageEmulator;
  final FunctionsEmulatorConnector _connectFunctionsEmulator;

  Future<bool> initialize() async {
    try {
      await _initializeApp(
        options: FirebaseOptionsSelector.forEnvironment(AppEnvironment.current),
      );
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

    // Each emulator connector below is deliberately a separate, non-fatal
    // step: a failure connecting any one of them (e.g. that particular
    // local emulator isn't running) must not undo a successful core
    // Firebase init, and must not stop the others from connecting — only
    // that one product's calls will fail at their own call site later, the
    // same fail-closed shape `ProductionUnavailableAuthRepository` already
    // establishes.
    //
    // Every product must be wired here, not just Auth: before this fix,
    // only `useAuthEmulator` was ever called, so Firestore/Storage/
    // Functions silently talked to the real backend on every environment,
    // including development — the specific cause of the real-device
    // `PERMISSION_DENIED` / real-project Firestore traffic this fix closes.
    if (FirebaseAuthEmulatorConfig.shouldUseEmulator(AppEnvironment.current)) {
      try {
        _connectAuthEmulator(
          FirebaseAuthEmulatorConfig.host,
          FirebaseAuthEmulatorConfig.port,
        );
      } catch (error, stackTrace) {
        final failure = ErrorMapper.map(error);
        _loggingService.log(
          LogLevel.error,
          'Firebase Auth Emulator connection failed: ${failure.message}',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    if (FirebaseFirestoreEmulatorConfig.shouldUseEmulator(
      AppEnvironment.current,
    )) {
      try {
        _connectFirestoreEmulator(
          FirebaseFirestoreEmulatorConfig.host,
          FirebaseFirestoreEmulatorConfig.port,
        );
      } catch (error, stackTrace) {
        final failure = ErrorMapper.map(error);
        _loggingService.log(
          LogLevel.error,
          'Firebase Firestore Emulator connection failed: ${failure.message}',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    if (FirebaseStorageEmulatorConfig.shouldUseEmulator(
      AppEnvironment.current,
    )) {
      try {
        _connectStorageEmulator(
          FirebaseStorageEmulatorConfig.host,
          FirebaseStorageEmulatorConfig.port,
        );
      } catch (error, stackTrace) {
        final failure = ErrorMapper.map(error);
        _loggingService.log(
          LogLevel.error,
          'Firebase Storage Emulator connection failed: ${failure.message}',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    if (FirebaseFunctionsEmulatorConfig.shouldUseEmulator(
      AppEnvironment.current,
    )) {
      try {
        _connectFunctionsEmulator(
          FirebaseFunctionsEmulatorConfig.host,
          FirebaseFunctionsEmulatorConfig.port,
        );
      } catch (error, stackTrace) {
        final failure = ErrorMapper.map(error);
        _loggingService.log(
          LogLevel.error,
          'Firebase Functions Emulator connection failed: ${failure.message}',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    return true;
  }
}
