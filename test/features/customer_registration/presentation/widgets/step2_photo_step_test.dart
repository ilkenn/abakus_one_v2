import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/customer_photos/data/customer_photo_gateway.dart';
import 'package:abakus_one_v2/features/customer_photos/data/customer_photo_picker.dart';
import 'package:abakus_one_v2/features/customer_photos/data/customer_photo_storage_client.dart';
import 'package:abakus_one_v2/features/customer_photos/presentation/providers/customer_photo_providers.dart';
import 'package:abakus_one_v2/features/customer_registration/presentation/widgets/step2_photo_step.dart';
import 'package:abakus_one_v2/shared/models/customer_photo.dart';
import 'package:abakus_one_v2/shared/models/customer_photo_status.dart';

// A real, minimal, valid 1x1 transparent PNG — `Image.memory` in
// `_PhotoPreview` actually decodes these bytes (unlike a plain zeroed
// `Uint8List`, which throws "Invalid image data" and fails the test via
// `FlutterError.onError`), so every test that reaches the preview state
// needs genuinely valid image bytes, not just a byte count. Top-level (not
// nested in `main()`) so `_FakeCustomerPhotoStorageClient.downloadBytes`
// can also return it, once the physical-device fix started using
// `customerPhotoBytesProvider` for a persisted photo's preview.
Uint8List validPngBytes() {
  return Uint8List.fromList(const [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
    0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, //
    0x54, 0x78, 0x9C, 0x63, 0x60, 0x60, 0x60, 0x60, //
    0x00, 0x00, 0x00, 0x05, 0x00, 0x01, 0x5A, 0x27, //
    0xDE, 0xFC, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, //
    0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82, //
  ]);
}

/// CR.1.2 — the deep pick/upload/retry/quota matrix for Step 2 of
/// onboarding, isolated from the full "Profilini Tamamla" screen (that
/// integration is covered, at a shallower level, by
/// `complete_profile_screen_test.dart`). Fakes mirror
/// `customer_photo_upload_provider_test.dart`'s exact established pattern
/// — the real Firebase-backed implementations are unavailable under
/// `flutter test`.
void main() {
  AuthState authenticatedState() {
    return AuthState(
      isAuthenticated: true,
      isGuest: false,
      session: AuthSession(
        uid: 'customer-uid-1',
        phoneNumber: '+905551234567',
        createdAt: DateTime(2026, 1, 1),
        expiresAt: DateTime(2027, 1, 1),
      ),
    );
  }

  CustomerPhoto samplePhoto({
    String id = 'p1',
    CustomerPhotoStatus status = CustomerPhotoStatus.approved,
    String customerId = 'customer-uid-1',
    String? purpose,
    String? rejectionReason,
  }) {
    return CustomerPhoto(
      id: id,
      customerId: customerId,
      organizationId: 'org-1',
      photoRef: 'tenants/org-1/customerPhotos/$customerId/$id',
      status: status,
      uploadedAt: DateTime(2026, 8, 1),
      revision: 1,
      purpose: purpose,
      rejectionReason: rejectionReason,
    );
  }

  PickedCustomerPhoto smallPickedPhoto() {
    return PickedCustomerPhoto(
      bytes: validPngBytes(),
      fileName: 'photo.png',
      mimeType: 'image/png',
    );
  }

  Future<void> pumpStep2(
    WidgetTester tester, {
    required _FakeCustomerPhotoGateway gateway,
    required _FakeCustomerPhotoStorageClient storageClient,
    required _FakeCustomerPhotoPicker picker,
    VoidCallback? onFinished,
    int? finishedCallCount,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider
              .overrideWith(() => SeededAuthNotifier(authenticatedState())),
          customerPhotoGatewayProvider.overrideWithValue(gateway),
          customerPhotoStorageClientProvider.overrideWithValue(storageClient),
          customerPhotoPickerProvider.overrideWithValue(picker),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Step2PhotoStep(onFinished: onFinished ?? () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Drives a Step 2 attempt through "Fotoğraf Ekle" -> "Galeriden Seç" up
  /// to the point where the notifier reports `waitingForFinalize` — the
  /// shared setup every "then the gallery emits the finalized photo" test
  /// below builds on.
  Future<void> uploadOnce(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('step2PhotoAddButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Galeriden Seç'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'idle state shows "Fotoğraf Ekle" and "Şimdilik Geç", no preview image yet',
      (tester) async {
    await pumpStep2(
      tester,
      gateway: _FakeCustomerPhotoGateway(),
      storageClient: _FakeCustomerPhotoStorageClient(),
      picker: _FakeCustomerPhotoPicker(result: null),
    );

    expect(find.byKey(const Key('step2PhotoAddButton')), findsOneWidget);
    expect(find.byKey(const Key('step2PhotoSkipButton')), findsOneWidget);
    expect(find.byKey(const Key('step2PhotoPreviewImage')), findsNothing);
  });

  testWidgets('"Şimdilik Geç" calls onFinished — the photo is optional',
      (tester) async {
    var finishedCalls = 0;
    await pumpStep2(
      tester,
      gateway: _FakeCustomerPhotoGateway(),
      storageClient: _FakeCustomerPhotoStorageClient(),
      picker: _FakeCustomerPhotoPicker(result: null),
      onFinished: () => finishedCalls++,
    );

    await tester.tap(find.byKey(const Key('step2PhotoSkipButton')));
    await tester.pumpAndSettle();

    expect(finishedCalls, 1);
  });

  testWidgets(
      'picking gallery/camera photo and a successful upload shows the local preview and "Onay Bekliyor"',
      (tester) async {
    final gateway = _FakeCustomerPhotoGateway(
      grantResult: CustomerPhotoUploadGrant(
        grantId: 'grant-1',
        objectPath: 'tenants/org-1/customerPhotos/customer-uid-1/grant-1',
        contentType: 'image/png',
        expiresAt: DateTime(2026, 8, 1, 12, 15),
      ),
    );
    await pumpStep2(
      tester,
      gateway: gateway,
      storageClient: _FakeCustomerPhotoStorageClient(),
      picker: _FakeCustomerPhotoPicker(result: smallPickedPhoto()),
    );

    await uploadOnce(tester);

    expect(find.byKey(const Key('step2PhotoPreviewImage')), findsOneWidget);
    expect(
        find.byKey(const Key('step2PhotoPendingReviewChip')), findsOneWidget);
    expect(find.text('Onay Bekliyor'), findsOneWidget);
    expect(
      find.byKey(const Key('step2PhotoPendingReviewExplanation')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('step2PhotoContinueButton')), findsOneWidget);
  });

  testWidgets(
      'the upload grant request carries purpose: profileOnboarding — server-authoritative intent',
      (tester) async {
    final gateway = _FakeCustomerPhotoGateway(
      grantResult: CustomerPhotoUploadGrant(
        grantId: 'grant-1',
        objectPath: 'tenants/org-1/customerPhotos/customer-uid-1/grant-1',
        contentType: 'image/png',
        expiresAt: DateTime(2026, 8, 1, 12, 15),
      ),
    );
    await pumpStep2(
      tester,
      gateway: gateway,
      storageClient: _FakeCustomerPhotoStorageClient(),
      picker: _FakeCustomerPhotoPicker(result: smallPickedPhoto()),
    );

    await tester.tap(find.byKey(const Key('step2PhotoAddButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kameradan Çek'));
    await tester.pumpAndSettle();

    expect(gateway.requestUploadGrantCalls, hasLength(1));
    expect(
      gateway.requestUploadGrantCalls.single['purpose'],
      'profileOnboarding',
    );
  });

  testWidgets('"Devam Et" after a successful upload calls onFinished',
      (tester) async {
    var finishedCalls = 0;
    final gateway = _FakeCustomerPhotoGateway(
      grantResult: CustomerPhotoUploadGrant(
        grantId: 'grant-1',
        objectPath: 'tenants/org-1/customerPhotos/customer-uid-1/grant-1',
        contentType: 'image/png',
        expiresAt: DateTime(2026, 8, 1, 12, 15),
      ),
    );
    await pumpStep2(
      tester,
      gateway: gateway,
      storageClient: _FakeCustomerPhotoStorageClient(),
      picker: _FakeCustomerPhotoPicker(result: smallPickedPhoto()),
      onFinished: () => finishedCalls++,
    );

    await uploadOnce(tester);

    await tester.tap(find.byKey(const Key('step2PhotoContinueButton')));
    await tester.pumpAndSettle();

    expect(finishedCalls, 1);
  });

  testWidgets(
      'an upload failure never calls onFinished automatically — shows "Tekrar Dene" and "Daha Sonra Ekle" instead',
      (tester) async {
    var finishedCalls = 0;
    final gateway = _FakeCustomerPhotoGateway(
      grantError: const CustomerPhotoGatewayException('unknown', 'boom'),
    );
    await pumpStep2(
      tester,
      gateway: gateway,
      storageClient: _FakeCustomerPhotoStorageClient(),
      picker: _FakeCustomerPhotoPicker(result: smallPickedPhoto()),
      onFinished: () => finishedCalls++,
    );

    await uploadOnce(tester);

    expect(finishedCalls, 0,
        reason: 'a failed upload must never break/finish registration');
    expect(find.byKey(const Key('step2PhotoRetryButton')), findsOneWidget);
    expect(find.byKey(const Key('step2PhotoLaterButton')), findsOneWidget);
    expect(find.byKey(const Key('step2PhotoErrorText')), findsOneWidget);
  });

  testWidgets(
      'a Storage upload failure (not just a grant failure) also shows the retry/later UI, never onFinished automatically',
      (tester) async {
    var finishedCalls = 0;
    final gateway = _FakeCustomerPhotoGateway(
      grantResult: CustomerPhotoUploadGrant(
        grantId: 'grant-1',
        objectPath: 'tenants/org-1/customerPhotos/customer-uid-1/grant-1',
        contentType: 'image/png',
        expiresAt: DateTime(2026, 8, 1, 12, 15),
      ),
    );
    final storageClient = _FakeCustomerPhotoStorageClient(
      uploadError:
          const CustomerPhotoStorageException('unknown', 'network down'),
    );
    await pumpStep2(
      tester,
      gateway: gateway,
      storageClient: storageClient,
      picker: _FakeCustomerPhotoPicker(result: smallPickedPhoto()),
      onFinished: () => finishedCalls++,
    );

    await uploadOnce(tester);

    expect(finishedCalls, 0);
    expect(find.byKey(const Key('step2PhotoRetryButton')), findsOneWidget);
    expect(find.byKey(const Key('step2PhotoLaterButton')), findsOneWidget);
  });

  testWidgets(
      '"Daha Sonra Ekle" after a failure calls onFinished — the failed upload never blocks onboarding',
      (tester) async {
    var finishedCalls = 0;
    final gateway = _FakeCustomerPhotoGateway(
      grantError: const CustomerPhotoGatewayException('unknown', 'boom'),
    );
    await pumpStep2(
      tester,
      gateway: gateway,
      storageClient: _FakeCustomerPhotoStorageClient(),
      picker: _FakeCustomerPhotoPicker(result: smallPickedPhoto()),
      onFinished: () => finishedCalls++,
    );

    await uploadOnce(tester);

    await tester.tap(find.byKey(const Key('step2PhotoLaterButton')));
    await tester.pumpAndSettle();

    expect(finishedCalls, 1);
  });

  testWidgets(
      '"Tekrar Dene" retries the SAME picked photo without re-opening the picker, and can succeed',
      (tester) async {
    final gateway = _FakeCustomerPhotoGateway(
      grantError: const CustomerPhotoGatewayException('unknown', 'boom'),
      grantResult: CustomerPhotoUploadGrant(
        grantId: 'grant-1',
        objectPath: 'tenants/org-1/customerPhotos/customer-uid-1/grant-1',
        contentType: 'image/png',
        expiresAt: DateTime(2026, 8, 1, 12, 15),
      ),
    );
    final picker = _FakeCustomerPhotoPicker(result: smallPickedPhoto());
    await pumpStep2(
      tester,
      gateway: gateway,
      storageClient: _FakeCustomerPhotoStorageClient(),
      picker: picker,
    );

    await uploadOnce(tester);
    expect(find.byKey(const Key('step2PhotoRetryButton')), findsOneWidget);
    expect(picker.callCount, 1);

    // The gateway now succeeds on the next attempt (simulates a transient
    // failure that clears up).
    gateway.grantError = null;
    await tester.tap(find.byKey(const Key('step2PhotoRetryButton')));
    await tester.pumpAndSettle();

    expect(picker.callCount, 1,
        reason:
            'retry reuses the already-picked photo — no second picker prompt');
    expect(find.byKey(const Key('step2PhotoContinueButton')), findsOneWidget);
    expect(gateway.requestUploadGrantCalls, hasLength(2));
  });

  testWidgets(
      'a double-tap on "Fotoğraf Ekle" never triggers two parallel upload attempts',
      (tester) async {
    final gateway = _FakeCustomerPhotoGateway(
      grantResult: CustomerPhotoUploadGrant(
        grantId: 'grant-1',
        objectPath: 'tenants/org-1/customerPhotos/customer-uid-1/grant-1',
        contentType: 'image/png',
        expiresAt: DateTime(2026, 8, 1, 12, 15),
      ),
    );
    final storageClient = _FakeCustomerPhotoStorageClient(
        uploadDelay: const Duration(milliseconds: 50));
    await pumpStep2(
      tester,
      gateway: gateway,
      storageClient: storageClient,
      picker: _FakeCustomerPhotoPicker(result: smallPickedPhoto()),
    );

    await tester.tap(find.byKey(const Key('step2PhotoAddButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Galeriden Seç'));
    // Deliberately no pumpAndSettle yet — the upload is still in flight
    // (storageClient has an artificial delay), matching the exact
    // duplicate-tap race this notifier's own guard is meant to close.
    await tester.pump();

    // The "Fotoğraf Ekle" button is gone during upload (idle-only UI), so
    // a genuine double-tap on the SAME control isn't reachable from the
    // UI itself — this proves the guard defends the notifier's own entry
    // point regardless.
    await tester.pumpAndSettle();

    expect(gateway.requestUploadGrantCalls, hasLength(1));
    expect(storageClient.uploadCalls, hasLength(1));
  });

  testWidgets(
      'when the gallery already has 10 eligible photos, "Fotoğraf Ekle" is unavailable but "Şimdilik Geç" remains',
      (tester) async {
    final gateway = _FakeCustomerPhotoGateway(
      galleryPhotos: List.generate(10, (i) => samplePhoto(id: 'p$i')),
    );
    var finishedCalls = 0;
    await pumpStep2(
      tester,
      gateway: gateway,
      storageClient: _FakeCustomerPhotoStorageClient(),
      picker: _FakeCustomerPhotoPicker(result: null),
      onFinished: () => finishedCalls++,
    );

    final addButton = tester.widget<ElevatedButton>(
      find.descendant(
        of: find.byKey(const Key('step2PhotoAddButton')),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(addButton.onPressed, isNull, reason: 'quota is full — disabled');

    await tester.tap(find.byKey(const Key('step2PhotoSkipButton')));
    await tester.pumpAndSettle();
    expect(finishedCalls, 1);
  });

  testWidgets('cancelling the source picker sheet leaves Step 2 idle',
      (tester) async {
    final gateway = _FakeCustomerPhotoGateway();
    await pumpStep2(
      tester,
      gateway: gateway,
      storageClient: _FakeCustomerPhotoStorageClient(),
      picker: _FakeCustomerPhotoPicker(result: null),
    );

    await tester.tap(find.byKey(const Key('step2PhotoAddButton')));
    await tester.pumpAndSettle();
    // Dismiss the sheet without choosing a source.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(gateway.requestUploadGrantCalls, isEmpty);
    expect(find.byKey(const Key('step2PhotoAddButton')), findsOneWidget);
  });

  testWidgets(
      'cancelling the image picker itself (after choosing a source) leaves Step 2 idle',
      (tester) async {
    final gateway = _FakeCustomerPhotoGateway();
    await pumpStep2(
      tester,
      gateway: gateway,
      storageClient: _FakeCustomerPhotoStorageClient(),
      picker: _FakeCustomerPhotoPicker(result: null),
    );

    await tester.tap(find.byKey(const Key('step2PhotoAddButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Galeriden Seç'));
    await tester.pumpAndSettle();

    expect(gateway.requestUploadGrantCalls, isEmpty);
    expect(find.byKey(const Key('step2PhotoAddButton')), findsOneWidget);
    expect(find.byKey(const Key('step2PhotoPreviewImage')), findsNothing);
  });

  // ===========================================================================
  // PHYSICAL-DEVICE REGRESSION — finalized-photo persistence survives the
  // upload notifier resetting to idle (2026-08-20).
  // ===========================================================================

  group('persisted attempt photo — physical-device regression', () {
    testWidgets(
        'REGRESSION: once the gallery emits the finalized photo and the upload provider resets to idle, Step 2 still shows the uploaded photo as pending — never reverts to the initial "Fotoğraf Ekle" state',
        (tester) async {
      final gateway = _FakeCustomerPhotoGateway(
        grantResult: CustomerPhotoUploadGrant(
          grantId: 'grant-1',
          objectPath: 'tenants/org-1/customerPhotos/customer-uid-1/grant-1',
          contentType: 'image/png',
          expiresAt: DateTime(2026, 8, 1, 12, 15),
        ),
      );
      await pumpStep2(
        tester,
        gateway: gateway,
        storageClient: _FakeCustomerPhotoStorageClient(),
        picker: _FakeCustomerPhotoPicker(result: smallPickedPhoto()),
      );

      await uploadOnce(tester);
      expect(find.byKey(const Key('step2PhotoContinueButton')), findsOneWidget);

      // The backend finalize trigger has now run and the gallery stream
      // has caught up — this resets `CustomerPhotoUploadNotifier` back
      // to `idle` internally. This is the EXACT physical-device race
      // this test reproduces.
      gateway.emitGallery([
        samplePhoto(
          id: 'grant-1',
          status: CustomerPhotoStatus.pendingReview,
          purpose: 'profileOnboarding',
        ),
      ]);
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('step2PhotoPendingReviewChip')), findsOneWidget,
          reason: '"Onay Bekliyor" must remain visible');
      expect(find.text('Onay Bekliyor'), findsOneWidget);
      expect(find.byKey(const Key('step2PhotoContinueButton')), findsOneWidget,
          reason: '"Devam Et" must remain available');
      expect(find.byKey(const Key('step2PhotoAddButton')), findsNothing,
          reason:
              'must NOT revert to the initial "Fotoğraf Ekle" state as though nothing was uploaded');
      expect(find.byKey(const Key('step2PhotoSkipButton')), findsNothing);
      expect(find.byKey(const Key('step2PhotoPreviewImage')), findsOneWidget);
    });

    testWidgets(
        'an unrelated photo (different id) in the gallery does not satisfy this attempt — Step 2 stays in the waiting state',
        (tester) async {
      final gateway = _FakeCustomerPhotoGateway(
        grantResult: CustomerPhotoUploadGrant(
          grantId: 'grant-1',
          objectPath: 'tenants/org-1/customerPhotos/customer-uid-1/grant-1',
          contentType: 'image/png',
          expiresAt: DateTime(2026, 8, 1, 12, 15),
        ),
      );
      await pumpStep2(
        tester,
        gateway: gateway,
        storageClient: _FakeCustomerPhotoStorageClient(),
        picker: _FakeCustomerPhotoPicker(result: smallPickedPhoto()),
      );

      await uploadOnce(tester);

      gateway.emitGallery([
        samplePhoto(
          id: 'some-other-photo',
          status: CustomerPhotoStatus.approved,
          purpose: 'profileOnboarding',
        ),
      ]);
      await tester.pumpAndSettle();

      // Still waiting on OUR attempt (grant-1) — an unrelated
      // profileOnboarding photo with a different id must never be
      // mistaken for it.
      expect(
          find.byKey(const Key('step2PhotoPendingReviewChip')), findsOneWidget);
      expect(
          find.byKey(const Key('step2PhotoPersistedStatusChip')), findsNothing);
    });

    testWidgets(
        'a persisted underReview status remains visible and allows continuing',
        (tester) async {
      final gateway = _FakeCustomerPhotoGateway(
        grantResult: CustomerPhotoUploadGrant(
          grantId: 'grant-1',
          objectPath: 'tenants/org-1/customerPhotos/customer-uid-1/grant-1',
          contentType: 'image/png',
          expiresAt: DateTime(2026, 8, 1, 12, 15),
        ),
      );
      await pumpStep2(
        tester,
        gateway: gateway,
        storageClient: _FakeCustomerPhotoStorageClient(),
        picker: _FakeCustomerPhotoPicker(result: smallPickedPhoto()),
      );

      await uploadOnce(tester);

      gateway.emitGallery([
        samplePhoto(
          id: 'grant-1',
          status: CustomerPhotoStatus.underReview,
          purpose: 'profileOnboarding',
        ),
      ]);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('step2PhotoPersistedStatusChip')),
          findsOneWidget);
      expect(find.text('İnceleniyor'), findsOneWidget);
      expect(find.byKey(const Key('step2PhotoContinueButton')), findsOneWidget);
    });

    testWidgets(
        'a persisted approved status remains visible and allows continuing',
        (tester) async {
      final gateway = _FakeCustomerPhotoGateway(
        grantResult: CustomerPhotoUploadGrant(
          grantId: 'grant-1',
          objectPath: 'tenants/org-1/customerPhotos/customer-uid-1/grant-1',
          contentType: 'image/png',
          expiresAt: DateTime(2026, 8, 1, 12, 15),
        ),
      );
      await pumpStep2(
        tester,
        gateway: gateway,
        storageClient: _FakeCustomerPhotoStorageClient(),
        picker: _FakeCustomerPhotoPicker(result: smallPickedPhoto()),
      );

      await uploadOnce(tester);

      gateway.emitGallery([
        samplePhoto(
          id: 'grant-1',
          status: CustomerPhotoStatus.approved,
          purpose: 'profileOnboarding',
        ),
      ]);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('step2PhotoPersistedStatusChip')),
          findsOneWidget);
      expect(find.text('Onaylandı'), findsOneWidget);
      expect(find.byKey(const Key('step2PhotoContinueButton')), findsOneWidget);
    });

    testWidgets(
        'a persisted rejected photo shows the private rejection status and allows retry/later, never onFinished automatically',
        (tester) async {
      var finishedCalls = 0;
      final gateway = _FakeCustomerPhotoGateway(
        grantResult: CustomerPhotoUploadGrant(
          grantId: 'grant-1',
          objectPath: 'tenants/org-1/customerPhotos/customer-uid-1/grant-1',
          contentType: 'image/png',
          expiresAt: DateTime(2026, 8, 1, 12, 15),
        ),
      );
      await pumpStep2(
        tester,
        gateway: gateway,
        storageClient: _FakeCustomerPhotoStorageClient(),
        picker: _FakeCustomerPhotoPicker(result: smallPickedPhoto()),
        onFinished: () => finishedCalls++,
      );

      await uploadOnce(tester);

      gateway.emitGallery([
        samplePhoto(
          id: 'grant-1',
          status: CustomerPhotoStatus.rejected,
          purpose: 'profileOnboarding',
          rejectionReason: 'bulanık',
        ),
      ]);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('step2PhotoPersistedStatusChip')),
          findsOneWidget);
      expect(find.text('Onaylanmadı'), findsOneWidget);
      expect(
          find.byKey(const Key('step2PhotoRejectionReason')), findsOneWidget);
      expect(find.text('bulanık'), findsOneWidget);
      expect(find.byKey(const Key('step2PhotoRetryButton')), findsOneWidget);
      expect(find.byKey(const Key('step2PhotoLaterButton')), findsOneWidget);
      expect(finishedCalls, 0);

      await tester.tap(find.byKey(const Key('step2PhotoLaterButton')));
      await tester.pumpAndSettle();
      expect(finishedCalls, 1);
    });

    testWidgets(
        '"Tekrar Dene" after a persisted rejection opens the picker again for a fresh photo, never resubmits the already-rejected bytes',
        (tester) async {
      final gateway = _FakeCustomerPhotoGateway(
        grantResult: CustomerPhotoUploadGrant(
          grantId: 'grant-1',
          objectPath: 'tenants/org-1/customerPhotos/customer-uid-1/grant-1',
          contentType: 'image/png',
          expiresAt: DateTime(2026, 8, 1, 12, 15),
        ),
      );
      final picker = _FakeCustomerPhotoPicker(result: smallPickedPhoto());
      await pumpStep2(
        tester,
        gateway: gateway,
        storageClient: _FakeCustomerPhotoStorageClient(),
        picker: picker,
      );

      await uploadOnce(tester);
      expect(picker.callCount, 1);

      gateway.emitGallery([
        samplePhoto(
          id: 'grant-1',
          status: CustomerPhotoStatus.rejected,
          purpose: 'profileOnboarding',
        ),
      ]);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('step2PhotoRetryButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Galeriden Seç'));
      await tester.pumpAndSettle();

      expect(picker.callCount, 2,
          reason:
              'a rejected attempt must prompt a fresh pick, never resubmit the same rejected bytes');
    });

    testWidgets(
        'normal Profile photo upload (no onboarding attempt id) never shows a persisted-status chip',
        (tester) async {
      // No upload was ever driven through Step 2 (`_attemptPhotoId` stays
      // null) — a gallery that happens to contain approved/rejected
      // photos from the ordinary "Profil Fotoğraflarım" flow must never
      // be mistaken for this screen's own onboarding attempt.
      final gateway = _FakeCustomerPhotoGateway(
        galleryPhotos: [
          samplePhoto(id: 'existing-1', status: CustomerPhotoStatus.approved),
          samplePhoto(id: 'existing-2', status: CustomerPhotoStatus.rejected),
        ],
      );
      await pumpStep2(
        tester,
        gateway: gateway,
        storageClient: _FakeCustomerPhotoStorageClient(),
        picker: _FakeCustomerPhotoPicker(result: null),
      );

      expect(find.byKey(const Key('step2PhotoAddButton')), findsOneWidget);
      expect(
          find.byKey(const Key('step2PhotoPersistedStatusChip')), findsNothing);
      expect(
          find.byKey(const Key('step2PhotoPendingReviewChip')), findsNothing);
    });
  });
}

class _FakeCustomerPhotoGateway implements CustomerPhotoGateway {
  _FakeCustomerPhotoGateway({
    this.grantResult,
    this.grantError,
    List<CustomerPhoto>? galleryPhotos,
  }) : _photos = galleryPhotos ?? const [];

  CustomerPhotoUploadGrant? grantResult;
  CustomerPhotoGatewayException? grantError;
  final List<Map<String, dynamic>> requestUploadGrantCalls = [];

  List<CustomerPhoto> _photos;
  final List<StreamController<List<CustomerPhoto>>> _controllers = [];

  /// Pushes a new gallery snapshot to every live subscriber — mirrors
  /// `customer_photo_upload_provider_test.dart`'s own fake, needed here
  /// so a test can simulate the backend finalize trigger actually
  /// running (and the notifier's own `ref.listen` observing it) AFTER
  /// the initial pump, not only as a fixed value at construction time.
  void emitGallery(List<CustomerPhoto> photos) {
    _photos = photos;
    for (final controller in _controllers) {
      if (!controller.isClosed) controller.add(photos);
    }
  }

  @override
  Stream<List<CustomerPhoto>> watchGallery({
    required String organizationId,
    required String customerId,
  }) {
    late StreamController<List<CustomerPhoto>> controller;
    controller = StreamController<List<CustomerPhoto>>(
      onListen: () => controller.add(_photos),
    );
    _controllers.add(controller);
    return controller.stream;
  }

  @override
  Future<CustomerPhotoUploadGrant> requestUploadGrant({
    required String organizationId,
    required String contentType,
    String? purpose,
  }) async {
    requestUploadGrantCalls.add({
      'organizationId': organizationId,
      'contentType': contentType,
      'purpose': purpose,
    });
    if (grantError != null) throw grantError!;
    return grantResult!;
  }

  @override
  Future<void> selectProfilePhoto({
    required String organizationId,
    required String photoId,
  }) =>
      throw UnimplementedError('not exercised by Step2PhotoStep');

  @override
  Stream<String?> watchSelectedProfilePhotoRef({
    required String organizationId,
    required String customerId,
  }) =>
      Stream.value(null);
}

class _FakeCustomerPhotoStorageClient implements CustomerPhotoStorageClient {
  _FakeCustomerPhotoStorageClient({
    this.uploadError,
    this.uploadDelay,
    Uint8List? downloadResult,
  }) : downloadResult = downloadResult ?? validPngBytes();

  final CustomerPhotoStorageException? uploadError;
  final Duration? uploadDelay;

  /// What [downloadBytes] resolves to — defaults to a real, decodable
  /// PNG so a persisted photo's `customerPhotoBytesProvider`-backed
  /// preview renders without a broken-image state; pass `null` to
  /// simulate "not readable/ready yet."
  Uint8List? downloadResult;
  final List<Map<String, dynamic>> uploadCalls = [];

  @override
  Future<void> uploadBytes({
    required String objectPath,
    required Uint8List bytes,
    required String contentType,
  }) async {
    uploadCalls.add({'objectPath': objectPath, 'contentType': contentType});
    if (uploadDelay != null) await Future<void>.delayed(uploadDelay!);
    if (uploadError != null) throw uploadError!;
  }

  @override
  Future<Uint8List?> downloadBytes(String objectPath) async => downloadResult;
}

class _FakeCustomerPhotoPicker implements CustomerPhotoPicker {
  _FakeCustomerPhotoPicker({this.result});

  final PickedCustomerPhoto? result;
  int callCount = 0;

  @override
  Future<PickedCustomerPhoto?> pickImage({
    required CustomerPhotoPickSource source,
  }) async {
    callCount++;
    return result;
  }
}
