import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/core/services/logging/log_level.dart';
import 'package:abakus_one_v2/core/services/logging/logging_service.dart';
import 'package:abakus_one_v2/features/customer_photos/data/customer_photo_upload_diagnostics.dart';

/// Profile P.4.3A — Storage Upload Control-Flow Diagnostic (2026-08-19).
/// `AppEnvironment.current` defaults to `development` under `flutter test`
/// (no `--dart-define=ENVIRONMENT` is passed by this suite), which is the
/// exact path these diagnostics are meant to be active on — the same
/// assumption every other development-only diagnostic test in this feature
/// already relies on (see `customer_photo_storage_client_test.dart`).
void main() {
  group('logUploadMilestone', () {
    test('logs at LogLevel.debug, prefixed, with the given context', () {
      final logger = _RecordingLoggingService();

      logUploadMilestone(
          logger, 'upload action entered', {'source': 'gallery'});

      expect(logger.entries, hasLength(1));
      expect(logger.entries.single.level, LogLevel.debug);
      expect(logger.entries.single.message,
          '[CustomerPhotoUpload] upload action entered');
      expect(logger.entries.single.context, {'source': 'gallery'});
    });

    test('defaults to an empty context when none is given', () {
      final logger = _RecordingLoggingService();

      logUploadMilestone(logger, 'putData completed successfully');

      expect(logger.entries.single.context, isEmpty);
    });
  });

  group('withUploadHangDiagnostic', () {
    test('passes through the future\'s value unchanged', () async {
      final logger = _RecordingLoggingService();

      final result = await withUploadHangDiagnostic(
        logger,
        'CustomerPhotoStorageClient.uploadBytes',
        Future.value(42),
      );

      expect(result, 42);
    });

    test('passes through the future\'s error unchanged', () async {
      final logger = _RecordingLoggingService();

      await expectLater(
        withUploadHangDiagnostic(
          logger,
          'CustomerPhotoStorageClient.uploadBytes',
          Future<int>.error(Exception('boom')),
        ),
        throwsA(isException),
      );
    });

    test(
        'never logs a "still pending" breadcrumb when the future completes '
        'before the threshold', () async {
      final logger = _RecordingLoggingService();

      await withUploadHangDiagnostic(
        logger,
        'CustomerPhotoStorageClient.uploadBytes',
        Future.value(1),
        threshold: const Duration(milliseconds: 200),
      );

      expect(logger.entries, isEmpty);
    });

    test(
        'logs a "still pending" breadcrumb once the future outlives the '
        'threshold — without altering the eventual result', () async {
      final logger = _RecordingLoggingService();

      final result = await withUploadHangDiagnostic(
        logger,
        'CustomerPhotoStorageClient.uploadBytes',
        Future.delayed(const Duration(milliseconds: 50), () => 7),
        threshold: const Duration(milliseconds: 10),
      );

      expect(result, 7);
      expect(logger.entries, hasLength(1));
      expect(
        logger.entries.single.message,
        contains('CustomerPhotoStorageClient.uploadBytes'),
      );
      expect(logger.entries.single.message, contains('still pending after 0s'));
    });
  });
}

class _LoggedEntry {
  _LoggedEntry(this.level, this.message, this.context);
  final LogLevel level;
  final String message;
  final Map<String, Object?> context;
}

class _RecordingLoggingService implements LoggingService {
  final List<_LoggedEntry> entries = [];

  @override
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) {
    entries.add(_LoggedEntry(level, message, context ?? const {}));
  }
}
