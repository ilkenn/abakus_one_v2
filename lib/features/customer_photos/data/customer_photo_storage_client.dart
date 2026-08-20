import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart' as storage;

import '../../../bootstrap/app_environment.dart';
import '../../../bootstrap/firebase_storage_emulator_config.dart';
import '../../../core/services/logging/log_level.dart';
import '../../../core/services/logging/logging_provider.dart';
import '../../../core/services/logging/logging_service.dart';
import 'customer_photo_upload_diagnostics.dart';

/// The narrow slice of Firebase Storage the customer photo flow needs,
/// behind an interface — mirrors `FirebaseAuthClient`'s "the real SDK is
/// unavailable under `flutter test`, wrap it" discipline.
///
/// **[downloadBytes] never produces a public download URL.** It reads the
/// object's raw bytes directly (`Reference.getData()`), which Firebase
/// Storage authorizes per-request against `storage.rules` (owner/staff/
/// same-tenant-selected-photo — whatever the current rule allows for the
/// caller) — no `getDownloadURL()` call anywhere in this file, and no
/// public token URL is ever stored as `photoRef`. `photoRef` remains the
/// opaque Storage object path end-to-end, exactly as the domain model's
/// own doc comment requires.
abstract interface class CustomerPhotoStorageClient {
  /// Uploads [bytes] to the EXACT [objectPath] a grant authorized —
  /// callers must never construct their own path.
  Future<void> uploadBytes({
    required String objectPath,
    required Uint8List bytes,
    required String contentType,
  });

  /// `null` if the object doesn't exist (not yet finalized) or the
  /// caller isn't authorized to read it — never thrown for a routine
  /// "not ready yet" during the pending-review window.
  Future<Uint8List?> downloadBytes(String objectPath);
}

/// Builds the exact, unit-tested diagnostic field set
/// [FirebaseCustomerPhotoStorageClient] logs on an upload failure — kept as
/// a pure, top-level function (not inlined) specifically so a test can
/// assert on its exact output shape, independent of the real
/// [storage.FirebaseStorage] SDK.
///
/// **Never includes**: auth/App Check tokens, upload-grant secrets beyond
/// the already-opaque [objectPath] the grant itself returned, or raw image
/// bytes — only [byteLength] (a count, not the content) is logged.
Map<String, Object?> buildUploadFailureLogContext({
  required Object error,
  required String objectPath,
  required String contentType,
  required int byteLength,
  required bool storageEmulatorActive,
}) {
  return {
    'exceptionType': error.runtimeType.toString(),
    'firebaseExceptionPlugin':
        error is storage.FirebaseException ? error.plugin : null,
    'firebaseExceptionCode':
        error is storage.FirebaseException ? error.code : null,
    'firebaseExceptionMessage':
        error is storage.FirebaseException ? error.message : null,
    'objectPath': objectPath,
    'contentType': contentType,
    'byteLength': byteLength,
    'storageEmulatorActive': storageEmulatorActive,
  };
}

class CustomerPhotoStorageException implements Exception {
  const CustomerPhotoStorageException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'CustomerPhotoStorageException($code): $message';
}

class FirebaseCustomerPhotoStorageClient implements CustomerPhotoStorageClient {
  FirebaseCustomerPhotoStorageClient({
    storage.FirebaseStorage? firebaseStorage,
    LoggingService? loggingService,
  })  : _storage = firebaseStorage ?? storage.FirebaseStorage.instance,
        _loggingService = loggingService ?? defaultLoggingService();

  // Deliberately `storage.FirebaseStorage.instance` — NEVER
  // `FirebaseStorage.instanceFor(...)`, which would construct a SEPARATE
  // instance `FirebaseBootstrapService`'s own `useStorageEmulator` call
  // (on `.instance`) never touches, silently bypassing the configured
  // emulator even in `AppEnvironment.development`. Mirrors the exact
  // `FirebaseFunctions.instance`-only discipline this codebase already
  // established after finding this precise class of bug once before (see
  // `docs/decisions.md` Paket Servis P.3 §D12,
  // `test/bootstrap/functions_emulator_routing_regression_test.dart`) —
  // `test/bootstrap/storage_emulator_routing_regression_test.dart` is the
  // analogous structural guard for this file.
  final storage.FirebaseStorage _storage;
  final LoggingService _loggingService;

  // Matches storage.rules' own isValidCustomerImageUpload() size cap —
  // a defensive upper bound for downloadBytes' own buffer, not a policy
  // decision made here.
  static const int _maxDownloadBytes = 5 * 1024 * 1024;

  @override
  Future<void> uploadBytes({
    required String objectPath,
    required Uint8List bytes,
    required String contentType,
  }) async {
    logUploadMilestone(
      _loggingService,
      'immediately before FirebaseStorage.ref(objectPath).putData',
      {
        'objectPath': objectPath,
        'contentType': contentType,
        'byteLength': bytes.length,
      },
    );
    try {
      await _storage
          .ref(objectPath)
          .putData(bytes, storage.SettableMetadata(contentType: contentType));
      logUploadMilestone(
        _loggingService,
        'putData completed successfully',
        {'objectPath': objectPath},
      );
    } catch (error, stackTrace) {
      // Logged BEFORE re-throwing/wrapping — a raw `catch` (not just `on
      // storage.FirebaseException`) so a genuinely unrecognized exception
      // shape (e.g. a low-level platform/network failure that never even
      // reached the emulator, such as a missing `adb reverse tcp:9199
      // tcp:9199` on a physical device) still gets diagnosed instead of
      // silently propagating as an opaque type this class doesn't handle.
      _logUploadFailure(
        error: error,
        stackTrace: stackTrace,
        objectPath: objectPath,
        contentType: contentType,
        byteLength: bytes.length,
      );
      if (error is storage.FirebaseException) {
        throw CustomerPhotoStorageException(
          error.code,
          error.message ?? 'Fotoğraf yüklenemedi.',
        );
      }
      throw const CustomerPhotoStorageException(
        'unknown',
        'Fotoğraf yüklenemedi.',
      );
    }
  }

  /// TEMPORARY_STORAGE_UPLOAD_DIAGNOSTIC — Profile P.4.3A physical-device
  /// investigation (2026-08-19). DEVELOPMENT-ONLY, gated explicitly on
  /// [AppEnvironment.current] (not merely on [LoggingService] already
  /// being silent in a release build — belt-and-suspenders, matching the
  /// task's own precise "development-only" wording). Routed through the
  /// existing [LoggingService]/`LogRedactor` boundary rather than a raw
  /// `print`/`debugPrint` — the same redaction/no-network/local-only
  /// guarantees every other log line in this app already gets, not a new,
  /// separate mechanism.
  ///
  /// **Never logs**: auth/App Check tokens, upload-grant secrets beyond
  /// the already-opaque `objectPath` the grant itself returned, or raw
  /// image bytes — see [buildUploadFailureLogContext] for the exact,
  /// unit-tested field list this can ever emit.
  void _logUploadFailure({
    required Object error,
    required StackTrace stackTrace,
    required String objectPath,
    required String contentType,
    required int byteLength,
  }) {
    if (AppEnvironment.current != AppEnvironment.development) return;

    _loggingService.log(
      LogLevel.error,
      '[CustomerPhotoUpload] putData threw',
      error: error,
      stackTrace: stackTrace,
      context: buildUploadFailureLogContext(
        error: error,
        objectPath: objectPath,
        contentType: contentType,
        byteLength: byteLength,
        storageEmulatorActive: FirebaseStorageEmulatorConfig.shouldUseEmulator(
          AppEnvironment.current,
        ),
      ),
    );
  }

  @override
  Future<Uint8List?> downloadBytes(String objectPath) async {
    try {
      return await _storage.ref(objectPath).getData(_maxDownloadBytes);
    } on storage.FirebaseException catch (error) {
      // object-not-found / unauthorized both resolve to "can't show this
      // yet" rather than a surfaced error — routine during the brief
      // window before finalize creates the CustomerPhoto record, or if
      // the rules-authorized state has since changed (e.g. deselected).
      if (error.code == 'object-not-found' || error.code == 'unauthorized') {
        return null;
      }
      rethrow;
    }
  }
}
