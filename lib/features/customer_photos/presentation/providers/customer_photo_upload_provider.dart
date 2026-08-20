import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../bootstrap/app_environment.dart';
import '../../../../core/services/logging/logging_provider.dart';
import '../../../../core/services/logging/logging_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/customer_photo_gateway.dart';
import '../../data/customer_photo_picker.dart';
import '../../data/customer_photo_storage_client.dart';
import '../../data/customer_photo_upload_diagnostics.dart';
import '../../domain/customer_photo_client_rules.dart';
import 'customer_photo_providers.dart';

/// Profile P.4.3A — drives the real upload sequence:
///
/// pick -> validate -> request grant -> upload to the EXACT granted path
/// -> wait for the backend finalize trigger to create the `CustomerPhoto`.
///
/// Never creates a `customerPhotos` document, never sets `status`/
/// `isSelectedAsProfilePhoto`/`customerPublicProfiles`/
/// `profilePicturePath` — every one of those stays server-only, exactly
/// as `functions/src/finalizeCustomerPhotoUpload.ts` already enforces
/// independently of whatever this client claims.
enum CustomerPhotoUploadPhase {
  idle,
  picking,
  requestingGrant,
  uploading,
  waitingForFinalize,
  failed,
}

class CustomerPhotoUploadState {
  const CustomerPhotoUploadState({
    this.phase = CustomerPhotoUploadPhase.idle,
    this.errorMessage,
    this.limitReached = false,
    this.pendingGrantId,
  });

  final CustomerPhotoUploadPhase phase;
  final String? errorMessage;

  /// Distinct from a generic [errorMessage] so the UI can show the exact
  /// locked max-10 copy rather than a generic failure string.
  final bool limitReached;

  /// The grant this upload attempt is (or was) tracking — used to detect,
  /// via `customerPhotoGalleryProvider`, the moment the backend finalize
  /// trigger has actually created the corresponding `CustomerPhoto`
  /// (its id is deterministically the grantId).
  final String? pendingGrantId;

  /// A request is genuinely in flight — the add-photo action must be
  /// disabled while this is true, the one mechanism preventing an
  /// accidental double-tap from creating parallel grants/uploads.
  /// [CustomerPhotoUploadPhase.picking] is included and set synchronously
  /// (before the picker is even awaited) specifically so this guard is
  /// airtight against two near-simultaneous calls, not merely safe in
  /// practice because a real picker UI blocks further taps.
  bool get isBusy =>
      phase == CustomerPhotoUploadPhase.picking ||
      phase == CustomerPhotoUploadPhase.requestingGrant ||
      phase == CustomerPhotoUploadPhase.uploading ||
      phase == CustomerPhotoUploadPhase.waitingForFinalize;

  CustomerPhotoUploadState copyWith({
    CustomerPhotoUploadPhase? phase,
    String? errorMessage,
    bool clearError = false,
    bool? limitReached,
    String? pendingGrantId,
    bool clearPendingGrantId = false,
  }) {
    return CustomerPhotoUploadState(
      phase: phase ?? this.phase,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      limitReached: limitReached ?? this.limitReached,
      pendingGrantId:
          clearPendingGrantId ? null : (pendingGrantId ?? this.pendingGrantId),
    );
  }
}

const String _kLimitReachedMessage =
    'En fazla 10 profil fotoğrafı ekleyebilirsin.';
const String _kGenericFailureMessage =
    'Fotoğraf yüklenemedi. Lütfen tekrar dene.';
const String _kUnsupportedImageMessage =
    'Bu dosya türü desteklenmiyor. Lütfen bir fotoğraf seç.';
const String _kOversizedImageMessage =
    'Fotoğraf çok büyük. Lütfen 5 MB\'tan küçük bir fotoğraf seç.';

/// DEVELOPMENT-ONLY breadcrumb threshold for the wait-for-finalize phase —
/// see [logUploadMilestone]'s own doc comment. Not a product timeout: the
/// phase itself never changes state when this fires, it only logs.
const Duration _kFinalizeWaitDiagnosticThreshold = Duration(seconds: 30);

class CustomerPhotoUploadNotifier
    extends AutoDisposeNotifier<CustomerPhotoUploadState> {
  Timer? _finalizeWaitTimer;

  @override
  CustomerPhotoUploadState build() {
    ref.onDispose(() => _finalizeWaitTimer?.cancel());

    // Auto-clears back to idle the moment the gallery's live stream shows
    // the photo this attempt was waiting on — the real, backend-confirmed
    // signal that finalize actually ran, never a client-side timer/guess.
    ref.listen(customerPhotoGalleryProvider, (previous, next) {
      final pendingGrantId = state.pendingGrantId;
      if (pendingGrantId == null) return;
      // `.valueOrNull` — never the unsafe `.value`, which rethrows the
      // underlying error when `next` is an `AsyncError` with no cached
      // previous value (exactly the state a Firebase-unavailable test
      // environment produces) — that unsafe access is the real root
      // cause `ProfileCustomerPhotosCard`'s own fix (same file's history)
      // disclosed; fixed here too before it could cause the identical
      // crash from inside this listener instead of a build method.
      final photos = next.valueOrNull;
      if (photos == null) return;
      final finalized = photos.any((photo) => photo.id == pendingGrantId);
      if (finalized) {
        _finalizeWaitTimer?.cancel();
        logUploadMilestone(
          ref.read(loggingServiceProvider),
          'customerPhotos document observed',
          {'grantId': pendingGrantId},
        );
        state = const CustomerPhotoUploadState();
      }
    });
    return const CustomerPhotoUploadState();
  }

  /// Returns `true` only once bytes have been successfully handed to
  /// Storage (the upload itself succeeded) — it does NOT wait for
  /// finalize; callers should treat a `true` result as "submitted,
  /// pending," not "already visible in the gallery."
  ///
  /// [purpose] — CR.1.2 — forwarded verbatim to
  /// [CustomerPhotoGateway.requestUploadGrant]; `null` for the ordinary
  /// "Profil Fotoğraflarım" flow, `'profileOnboarding'` for the optional
  /// photo step during first-time registration.
  Future<bool> pickAndUpload({
    required CustomerPhotoPickSource source,
    String? purpose,
  }) async {
    final loggingService = ref.read(loggingServiceProvider);
    logUploadMilestone(loggingService, 'upload action entered', {
      'source': source.name,
    });

    // Duplicate-tap guard — the single mechanism preventing two parallel
    // grants/uploads from an accidental double-press. Setting `picking`
    // SYNCHRONOUSLY (before the first `await`) closes the race a second
    // call arriving before the picker resolves would otherwise slip
    // through — Dart's single-threaded event loop guarantees this
    // synchronous prefix always completes before a second invocation's
    // own `isBusy` check runs.
    if (state.isBusy) return false;
    state = state.copyWith(
      phase: CustomerPhotoUploadPhase.picking,
      clearError: true,
      limitReached: false,
    );

    final picked =
        await ref.read(customerPhotoPickerProvider).pickImage(source: source);
    if (picked == null) {
      // Cancelled — never an error, stays idle silently.
      logUploadMilestone(loggingService, 'image picker completed', {
        'cancelled': true,
      });
      state = const CustomerPhotoUploadState();
      return false;
    }
    logUploadMilestone(loggingService, 'image picker completed', {
      'cancelled': false,
      'mimeType': picked.mimeType,
      'byteLength': picked.bytes.length,
    });

    return _validateAndUpload(picked, loggingService, purpose: purpose);
  }

  /// CR.1.2 — for a caller that already has picked bytes in hand (e.g.
  /// `Step2PhotoStep`, which picks via [CustomerPhotoPicker] itself first
  /// so it can show the bytes as an instant local preview before/during
  /// upload) and wants to upload them without a second, redundant picker
  /// invocation. Shares every validation/grant/upload step [pickAndUpload]
  /// itself uses via [_validateAndUpload] — no duplicated business logic.
  Future<bool> uploadPicked({
    required PickedCustomerPhoto picked,
    String? purpose,
  }) async {
    final loggingService = ref.read(loggingServiceProvider);
    // Same synchronous duplicate-tap guard as `pickAndUpload` — closes the
    // identical race for callers of this entry point too.
    if (state.isBusy) return false;
    state = state.copyWith(
      phase: CustomerPhotoUploadPhase.picking,
      clearError: true,
      limitReached: false,
    );
    return _validateAndUpload(picked, loggingService, purpose: purpose);
  }

  Future<bool> _validateAndUpload(
    PickedCustomerPhoto picked,
    LoggingService loggingService, {
    String? purpose,
  }) async {
    final contentType = resolveCustomerPhotoContentType(
      mimeType: picked.mimeType,
      fileName: picked.fileName,
    );
    if (!isSupportedCustomerPhotoContentType(contentType)) {
      state = state.copyWith(
        phase: CustomerPhotoUploadPhase.failed,
        errorMessage: _kUnsupportedImageMessage,
        limitReached: false,
      );
      return false;
    }
    if (picked.bytes.length > kMaxCustomerPhotoUploadBytes) {
      state = state.copyWith(
        phase: CustomerPhotoUploadPhase.failed,
        errorMessage: _kOversizedImageMessage,
        limitReached: false,
      );
      return false;
    }
    logUploadMilestone(loggingService, 'client validation passed', {
      'contentType': contentType,
      'byteLength': picked.bytes.length,
    });

    // CR.1.2 — sourced from `authProvider`'s own session uid directly,
    // never `features/profile`'s `profileProvider` (this module is now
    // shared between `features/profile` and `features/customer_registration`
    // and cannot reach into either feature's own presentation layer —
    // `profileProvider` itself only ever derived this same uid from
    // `authProvider` in the first place, so this is a same-value swap).
    final customerId = ref.read(authProvider).session?.uid;
    if (customerId == null) {
      // Structurally shouldn't be reachable — the entry point that
      // triggers this is authenticated-only — but never proceed with a
      // null identity regardless.
      state = state.copyWith(
        phase: CustomerPhotoUploadPhase.failed,
        errorMessage: _kGenericFailureMessage,
        limitReached: false,
      );
      return false;
    }
    final organizationId = ref.read(currentCustomerOrganizationIdProvider);

    state = state.copyWith(
      phase: CustomerPhotoUploadPhase.requestingGrant,
      clearError: true,
      limitReached: false,
    );

    logUploadMilestone(loggingService, 'upload grant request started', {
      'organizationId': organizationId,
    });
    CustomerPhotoUploadGrant grant;
    try {
      grant = await ref.read(customerPhotoGatewayProvider).requestUploadGrant(
            organizationId: organizationId,
            contentType: contentType!,
            purpose: purpose,
          );
    } on CustomerPhotoGatewayException catch (error) {
      final isLimitReached = error.code == 'resource-exhausted';
      state = state.copyWith(
        phase: CustomerPhotoUploadPhase.failed,
        errorMessage:
            isLimitReached ? _kLimitReachedMessage : _kGenericFailureMessage,
        limitReached: isLimitReached,
        clearPendingGrantId: true,
      );
      return false;
    }
    logUploadMilestone(loggingService, 'upload grant received', {
      'grantId': grant.grantId,
      'objectPath': grant.objectPath,
      'contentType': grant.contentType,
    });

    state = state.copyWith(
      phase: CustomerPhotoUploadPhase.uploading,
      pendingGrantId: grant.grantId,
    );

    logUploadMilestone(
      loggingService,
      'immediately before CustomerPhotoStorageClient.uploadBytes',
      {'objectPath': grant.objectPath},
    );
    try {
      await withUploadHangDiagnostic(
        loggingService,
        'CustomerPhotoStorageClient.uploadBytes',
        ref.read(customerPhotoStorageClientProvider).uploadBytes(
              objectPath: grant.objectPath,
              bytes: picked.bytes,
              contentType: grant.contentType,
            ),
      );
    } on CustomerPhotoStorageException {
      state = state.copyWith(
        phase: CustomerPhotoUploadPhase.failed,
        errorMessage: _kGenericFailureMessage,
        limitReached: false,
      );
      return false;
    }

    // Bytes are uploaded — now waiting on the backend finalize trigger.
    // Never claimed as a failure merely because it hasn't happened yet;
    // build()'s ref.listen above clears this back to idle once the
    // gallery stream confirms it.
    logUploadMilestone(loggingService, 'waiting-for-finalize phase entered', {
      'grantId': grant.grantId,
    });
    state = state.copyWith(phase: CustomerPhotoUploadPhase.waitingForFinalize);
    _armFinalizeWaitDiagnostic(loggingService, grant.grantId);
    return true;
  }

  /// DEVELOPMENT-ONLY breadcrumb only — never marks the upload failed and
  /// never touches [state]. The real "did finalize actually happen" signal
  /// stays exactly what it already was: `build()`'s `ref.listen` on
  /// [customerPhotoGalleryProvider], which reflects backend truth whenever
  /// it arrives, however late. This just makes a since-elapsed wait with
  /// no result yet observable instead of indistinguishable from "still
  /// working normally."
  void _armFinalizeWaitDiagnostic(
    LoggingService loggingService,
    String grantId,
  ) {
    if (AppEnvironment.current != AppEnvironment.development) return;
    _finalizeWaitTimer?.cancel();
    _finalizeWaitTimer = Timer(_kFinalizeWaitDiagnosticThreshold, () {
      if (state.pendingGrantId != grantId ||
          state.phase != CustomerPhotoUploadPhase.waitingForFinalize) {
        return;
      }
      logUploadMilestone(
        loggingService,
        'finalize wait timed out / failed',
        {
          'grantId': grantId,
          'waitedSeconds': _kFinalizeWaitDiagnosticThreshold.inSeconds,
        },
      );
    });
  }

  void dismissError() {
    state = const CustomerPhotoUploadState();
  }
}

final customerPhotoUploadProvider = NotifierProvider.autoDispose<
    CustomerPhotoUploadNotifier, CustomerPhotoUploadState>(
  CustomerPhotoUploadNotifier.new,
);
