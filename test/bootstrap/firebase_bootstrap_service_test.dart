import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/bootstrap/firebase_auth_emulator_config.dart';
import 'package:abakus_one_v2/bootstrap/firebase_bootstrap_service.dart';
import 'package:abakus_one_v2/bootstrap/firebase_firestore_emulator_config.dart';
import 'package:abakus_one_v2/bootstrap/firebase_functions_emulator_config.dart';
import 'package:abakus_one_v2/bootstrap/firebase_storage_emulator_config.dart';
import 'package:abakus_one_v2/core/services/logging/log_level.dart';
import 'package:abakus_one_v2/core/services/logging/logging_service.dart';

class _RecordingLoggingService implements LoggingService {
  final List<LogLevel> levels = [];
  final List<String> messages = [];
  final List<Object?> errors = [];

  @override
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) {
    levels.add(level);
    messages.add(message);
    errors.add(error);
  }
}

void main() {
  group('FirebaseBootstrapService.initialize — success', () {
    test('returns true and logs nothing when initialization succeeds',
        () async {
      final logger = _RecordingLoggingService();
      final service = FirebaseBootstrapService(
        loggingService: logger,
        connectAuthEmulator: (host, port) async {},
        connectFirestoreEmulator: (host, port) {},
        connectStorageEmulator: (host, port) async {},
        connectFunctionsEmulator: (host, port) {},
        initializeApp: ({options}) async {},
      );

      final result = await service.initialize();

      expect(result, isTrue);
      expect(logger.messages, isEmpty);
    });

    test(
        'connects the Auth Emulator using FirebaseAuthEmulatorConfig\'s '
        'host/port — AppEnvironment.current defaults to development under '
        '`flutter test`', () async {
      final logger = _RecordingLoggingService();
      String? connectedHost;
      int? connectedPort;
      final service = FirebaseBootstrapService(
        loggingService: logger,
        connectAuthEmulator: (host, port) async {
          connectedHost = host;
          connectedPort = port;
        },
        connectFirestoreEmulator: (host, port) {},
        connectStorageEmulator: (host, port) async {},
        connectFunctionsEmulator: (host, port) {},
        initializeApp: ({options}) async {},
      );

      await service.initialize();

      expect(connectedHost, FirebaseAuthEmulatorConfig.host);
      expect(connectedPort, FirebaseAuthEmulatorConfig.port);
    });

    test(
        'a failure connecting the Auth Emulator is caught and logged, but '
        'does not undo an otherwise-successful core Firebase init', () async {
      final logger = _RecordingLoggingService();
      final service = FirebaseBootstrapService(
        loggingService: logger,
        connectAuthEmulator: (host, port) async {
          throw StateError('emulator not running');
        },
        connectFirestoreEmulator: (host, port) {},
        connectStorageEmulator: (host, port) async {},
        connectFunctionsEmulator: (host, port) {},
        initializeApp: ({options}) async {},
      );

      final result = await service.initialize();

      expect(result, isTrue);
      expect(logger.levels, [LogLevel.error]);
      expect(
        logger.messages.single,
        contains('Firebase Auth Emulator connection failed'),
      );
    });

    test(
        'connects the Firestore Emulator using '
        'FirebaseFirestoreEmulatorConfig\'s host/port', () async {
      final logger = _RecordingLoggingService();
      String? connectedHost;
      int? connectedPort;
      final service = FirebaseBootstrapService(
        loggingService: logger,
        connectAuthEmulator: (host, port) async {},
        connectFirestoreEmulator: (host, port) {
          connectedHost = host;
          connectedPort = port;
        },
        connectStorageEmulator: (host, port) async {},
        connectFunctionsEmulator: (host, port) {},
        initializeApp: ({options}) async {},
      );

      await service.initialize();

      expect(connectedHost, FirebaseFirestoreEmulatorConfig.host);
      expect(connectedPort, FirebaseFirestoreEmulatorConfig.port);
    });

    test(
        'a failure connecting the Firestore Emulator is caught and logged, '
        'but does not undo an otherwise-successful core Firebase init',
        () async {
      final logger = _RecordingLoggingService();
      final service = FirebaseBootstrapService(
        loggingService: logger,
        connectAuthEmulator: (host, port) async {},
        connectFirestoreEmulator: (host, port) {
          throw StateError('emulator not running');
        },
        connectStorageEmulator: (host, port) async {},
        connectFunctionsEmulator: (host, port) {},
        initializeApp: ({options}) async {},
      );

      final result = await service.initialize();

      expect(result, isTrue);
      expect(logger.levels, [LogLevel.error]);
      expect(
        logger.messages.single,
        contains('Firebase Firestore Emulator connection failed'),
      );
    });

    test(
        'connects the Storage Emulator using '
        'FirebaseStorageEmulatorConfig\'s host/port', () async {
      final logger = _RecordingLoggingService();
      String? connectedHost;
      int? connectedPort;
      final service = FirebaseBootstrapService(
        loggingService: logger,
        connectAuthEmulator: (host, port) async {},
        connectFirestoreEmulator: (host, port) {},
        connectStorageEmulator: (host, port) async {
          connectedHost = host;
          connectedPort = port;
        },
        connectFunctionsEmulator: (host, port) {},
        initializeApp: ({options}) async {},
      );

      await service.initialize();

      expect(connectedHost, FirebaseStorageEmulatorConfig.host);
      expect(connectedPort, FirebaseStorageEmulatorConfig.port);
    });

    test(
        'a failure connecting the Storage Emulator is caught and logged, '
        'but does not undo an otherwise-successful core Firebase init',
        () async {
      final logger = _RecordingLoggingService();
      final service = FirebaseBootstrapService(
        loggingService: logger,
        connectAuthEmulator: (host, port) async {},
        connectFirestoreEmulator: (host, port) {},
        connectStorageEmulator: (host, port) async {
          throw StateError('emulator not running');
        },
        connectFunctionsEmulator: (host, port) {},
        initializeApp: ({options}) async {},
      );

      final result = await service.initialize();

      expect(result, isTrue);
      expect(logger.levels, [LogLevel.error]);
      expect(
        logger.messages.single,
        contains('Firebase Storage Emulator connection failed'),
      );
    });

    test(
        'connects the Functions Emulator using '
        'FirebaseFunctionsEmulatorConfig\'s host/port', () async {
      final logger = _RecordingLoggingService();
      String? connectedHost;
      int? connectedPort;
      final service = FirebaseBootstrapService(
        loggingService: logger,
        connectAuthEmulator: (host, port) async {},
        connectFirestoreEmulator: (host, port) {},
        connectStorageEmulator: (host, port) async {},
        connectFunctionsEmulator: (host, port) {
          connectedHost = host;
          connectedPort = port;
        },
        initializeApp: ({options}) async {},
      );

      await service.initialize();

      expect(connectedHost, FirebaseFunctionsEmulatorConfig.host);
      expect(connectedPort, FirebaseFunctionsEmulatorConfig.port);
    });

    test(
        'a failure connecting the Functions Emulator is caught and logged, '
        'but does not undo an otherwise-successful core Firebase init',
        () async {
      final logger = _RecordingLoggingService();
      final service = FirebaseBootstrapService(
        loggingService: logger,
        connectAuthEmulator: (host, port) async {},
        connectFirestoreEmulator: (host, port) {},
        connectStorageEmulator: (host, port) async {},
        connectFunctionsEmulator: (host, port) {
          throw StateError('emulator not running');
        },
        initializeApp: ({options}) async {},
      );

      final result = await service.initialize();

      expect(result, isTrue);
      expect(logger.levels, [LogLevel.error]);
      expect(
        logger.messages.single,
        contains('Firebase Functions Emulator connection failed'),
      );
    });
  });

  group('FirebaseBootstrapService.initialize — failure', () {
    test('returns false, never throws, when initialization fails', () async {
      final logger = _RecordingLoggingService();
      final service = FirebaseBootstrapService(
        loggingService: logger,
        connectAuthEmulator: (host, port) async {},
        initializeApp: ({options}) async {
          throw Exception('network unavailable');
        },
      );

      final result = await service.initialize();

      expect(result, isFalse);
    });

    test('logs the failure at error severity, mapped through ErrorMapper',
        () async {
      final logger = _RecordingLoggingService();
      final service = FirebaseBootstrapService(
        loggingService: logger,
        connectAuthEmulator: (host, port) async {},
        initializeApp: ({options}) async {
          throw Exception('network unavailable');
        },
      );

      await service.initialize();

      expect(logger.levels, [LogLevel.error]);
      expect(logger.errors.single, isA<Exception>());
    });

    test(
        'never logs the raw exception message as the log message itself '
        '— only ErrorMapper\'s generic, user-safe Failure.message', () async {
      final logger = _RecordingLoggingService();
      const secretLookingMessage =
          'apiKey=AIzaSySECRETLOOKINGVALUE rejected by server';
      final service = FirebaseBootstrapService(
        loggingService: logger,
        connectAuthEmulator: (host, port) async {},
        initializeApp: ({options}) async {
          throw Exception(secretLookingMessage);
        },
      );

      await service.initialize();

      expect(logger.messages.single, isNot(contains('AIzaSy')));
    });

    test('propagates no exception out of initialize() itself', () async {
      final logger = _RecordingLoggingService();
      final service = FirebaseBootstrapService(
        loggingService: logger,
        connectAuthEmulator: (host, port) async {},
        initializeApp: ({options}) async {
          throw StateError('unexpected SDK state');
        },
      );

      await expectLater(service.initialize(), completes);
    });
  });
}
