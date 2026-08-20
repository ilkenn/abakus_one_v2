import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/core/services/logging/log_level.dart';
import 'package:abakus_one_v2/core/services/logging/logging_provider.dart';
import 'package:abakus_one_v2/core/services/logging/logging_service.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/customer_photos/data/customer_photo_gateway.dart';
import 'package:abakus_one_v2/features/customer_photos/data/customer_photo_picker.dart';
import 'package:abakus_one_v2/features/customer_photos/data/customer_photo_storage_client.dart';
import 'package:abakus_one_v2/features/customer_photos/presentation/providers/customer_photo_providers.dart';
import 'package:abakus_one_v2/features/customer_photos/presentation/providers/customer_photo_upload_provider.dart';
import 'package:abakus_one_v2/shared/models/customer_photo.dart';
import 'package:abakus_one_v2/shared/models/customer_photo_status.dart';

/// Profile P.4.3A — covers the CONFIG/GATEWAY, GALLERY STATE, and UPLOAD
/// required test groups. Real Firebase (`FirebaseCustomerPhotoGateway`/
/// `FirebaseCustomerPhotoStorageClient`/`ImagePickerCustomerPhotoPicker`)
/// is unavailable under `flutter test` (platform-channel/network backed,
/// same reasoning `FirebaseAuthClient`'s own doc comment already
/// establishes) — every test here uses fakes implementing the same
/// interfaces, mirroring `quick_test_login_provider_test.dart`'s exact
/// pattern.
void main() {
  AuthState authenticatedState({String uid = 'customer-uid-1'}) {
    return AuthState(
      isAuthenticated: true,
      isGuest: false,
      session: AuthSession(
        uid: uid,
        phoneNumber: '+905551234567',
        createdAt: DateTime(2026, 1, 1),
        expiresAt: DateTime(2027, 1, 1),
      ),
    );
  }

  ProviderContainer buildContainer({
    AuthState? authState,
    required _FakeCustomerPhotoGateway gateway,
    required _FakeCustomerPhotoStorageClient storageClient,
    required _FakeCustomerPhotoPicker picker,
    LoggingService? loggingService,
  }) {
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          () => SeededAuthNotifier(authState ?? authenticatedState()),
        ),
        customerPhotoGatewayProvider.overrideWithValue(gateway),
        customerPhotoStorageClientProvider.overrideWithValue(storageClient),
        customerPhotoPickerProvider.overrideWithValue(picker),
        if (loggingService != null)
          loggingServiceProvider.overrideWithValue(loggingService),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  CustomerPhoto samplePhoto({
    String id = 'grant-1',
    String customerId = 'customer-uid-1',
    CustomerPhotoStatus status = CustomerPhotoStatus.pendingReview,
    bool selected = false,
    String? rejectionReason,
  }) {
    return CustomerPhoto(
      id: id,
      customerId: customerId,
      organizationId: 'org-1',
      photoRef: 'tenants/org-1/customerPhotos/$customerId/$id',
      status: status,
      isSelectedAsProfilePhoto: selected,
      uploadedAt: DateTime(2026, 8, 1),
      rejectionReason: rejectionReason,
      revision: 1,
    );
  }

  PickedCustomerPhoto smallPickedPhoto({int bytes = 1024}) {
    return PickedCustomerPhoto(
      bytes: Uint8List(bytes),
      fileName: 'photo.png',
      mimeType: 'image/png',
    );
  }

  // =========================================================================
  // GALLERY STATE
  // =========================================================================

  group('customerPhotoGalleryProvider', () {
    test('loading — the initial state before the first snapshot arrives',
        () async {
      final gateway = _FakeCustomerPhotoGateway();
      final container = buildContainer(
        gateway: gateway,
        storageClient: _FakeCustomerPhotoStorageClient(),
        picker: _FakeCustomerPhotoPicker(),
      );

      expect(container.read(customerPhotoGalleryProvider).isLoading, isTrue);
      await container.read(customerPhotoGalleryProvider.future);
    });

    test('empty — the customer has no photos yet', () async {
      final gateway = _FakeCustomerPhotoGateway();
      final container = buildContainer(
        gateway: gateway,
        storageClient: _FakeCustomerPhotoStorageClient(),
        picker: _FakeCustomerPhotoPicker(),
      );

      gateway.emitGallery([]);
      final photos = await container.read(customerPhotoGalleryProvider.future);
      expect(photos, isEmpty);
    });

    test(
        'data — pendingReview/underReview/approved/rejected all surface correctly',
        () async {
      final gateway = _FakeCustomerPhotoGateway();
      final container = buildContainer(
        gateway: gateway,
        storageClient: _FakeCustomerPhotoStorageClient(),
        picker: _FakeCustomerPhotoPicker(),
      );

      final seeded = [
        samplePhoto(id: 'p1', status: CustomerPhotoStatus.pendingReview),
        samplePhoto(id: 'p2', status: CustomerPhotoStatus.underReview),
        samplePhoto(id: 'p3', status: CustomerPhotoStatus.approved),
        samplePhoto(
            id: 'p4',
            status: CustomerPhotoStatus.rejected,
            rejectionReason: 'bulanık'),
      ];
      gateway.emitGallery(seeded);

      final photos = await container.read(customerPhotoGalleryProvider.future);
      expect(photos.map((p) => p.id).toSet(), {'p1', 'p2', 'p3', 'p4'});
      expect(
        photos.firstWhere((p) => p.id == 'p4').rejectionReason,
        'bulanık',
      );
    });

    test('active count excludes rejected/removed — countsTowardEligibleLimit',
        () async {
      final gateway = _FakeCustomerPhotoGateway();
      final container = buildContainer(
        gateway: gateway,
        storageClient: _FakeCustomerPhotoStorageClient(),
        picker: _FakeCustomerPhotoPicker(),
      );

      gateway.emitGallery([
        samplePhoto(id: 'p1', status: CustomerPhotoStatus.pendingReview),
        samplePhoto(id: 'p2', status: CustomerPhotoStatus.underReview),
        samplePhoto(id: 'p3', status: CustomerPhotoStatus.approved),
        samplePhoto(id: 'p4', status: CustomerPhotoStatus.rejected),
        samplePhoto(id: 'p5', status: CustomerPhotoStatus.removed),
      ]);

      final photos = await container.read(customerPhotoGalleryProvider.future);
      final activeCount =
          photos.where((p) => p.countsTowardEligibleLimit).length;
      expect(activeCount, 3,
          reason: 'only pendingReview/underReview/approved count');
    });

    test(
        'signed-out identity resolves to an empty gallery, never an error/crash',
        () async {
      final gateway = _FakeCustomerPhotoGateway();
      final container = buildContainer(
        authState: const AuthState(isAuthenticated: false, isGuest: true),
        gateway: gateway,
        storageClient: _FakeCustomerPhotoStorageClient(),
        picker: _FakeCustomerPhotoPicker(),
      );

      final photos = await container.read(customerPhotoGalleryProvider.future);
      expect(photos, isEmpty);
      expect(gateway.watchGalleryCalls, isEmpty,
          reason: 'never even asks the backend without a real uid');
    });
  });

  // =========================================================================
  // UPLOAD
  // =========================================================================

  group('CustomerPhotoUploadNotifier.pickAndUpload', () {
    test(
        'picker cancellation is not an error — stays idle, no grant/upload requested',
        () async {
      final gateway = _FakeCustomerPhotoGateway();
      final storageClient = _FakeCustomerPhotoStorageClient();
      final container = buildContainer(
        gateway: gateway,
        storageClient: storageClient,
        picker: _FakeCustomerPhotoPicker(result: null),
      );

      final success = await container
          .read(customerPhotoUploadProvider.notifier)
          .pickAndUpload(source: CustomerPhotoPickSource.gallery);

      expect(success, isFalse);
      expect(container.read(customerPhotoUploadProvider).phase,
          CustomerPhotoUploadPhase.idle);
      expect(container.read(customerPhotoUploadProvider).errorMessage, isNull);
      expect(gateway.requestUploadGrantCalls, isEmpty);
      expect(storageClient.uploadCalls, isEmpty);
    });

    test(
        'a valid image requests an upload grant with the correct organizationId/contentType',
        () async {
      final gateway = _FakeCustomerPhotoGateway(
        grantResult: CustomerPhotoUploadGrant(
          grantId: 'grant-1',
          objectPath: 'tenants/org-1/customerPhotos/customer-uid-1/grant-1',
          contentType: 'image/png',
          expiresAt: DateTime(2026, 8, 1, 12, 15),
        ),
      );
      final storageClient = _FakeCustomerPhotoStorageClient();
      final container = buildContainer(
        gateway: gateway,
        storageClient: storageClient,
        picker: _FakeCustomerPhotoPicker(result: smallPickedPhoto()),
      );

      await container
          .read(customerPhotoUploadProvider.notifier)
          .pickAndUpload(source: CustomerPhotoPickSource.gallery);

      expect(gateway.requestUploadGrantCalls, hasLength(1));
      expect(gateway.requestUploadGrantCalls.single['organizationId'], 'org-1');
      expect(
          gateway.requestUploadGrantCalls.single['contentType'], 'image/png');
    });

    test(
        'uploads to the EXACT server-returned objectPath — never a client-constructed one',
        () async {
      const grantedPath =
          'tenants/org-1/customerPhotos/customer-uid-1/grant-xyz';
      final gateway = _FakeCustomerPhotoGateway(
        grantResult: CustomerPhotoUploadGrant(
          grantId: 'grant-xyz',
          objectPath: grantedPath,
          contentType: 'image/png',
          expiresAt: DateTime(2026, 8, 1, 12, 15),
        ),
      );
      final storageClient = _FakeCustomerPhotoStorageClient();
      final container = buildContainer(
        gateway: gateway,
        storageClient: storageClient,
        picker: _FakeCustomerPhotoPicker(result: smallPickedPhoto()),
      );

      final success = await container
          .read(customerPhotoUploadProvider.notifier)
          .pickAndUpload(source: CustomerPhotoPickSource.camera);

      expect(success, isTrue);
      expect(storageClient.uploadCalls, hasLength(1));
      expect(storageClient.uploadCalls.single['objectPath'], grantedPath);
      expect(
        container.read(customerPhotoUploadProvider).phase,
        CustomerPhotoUploadPhase.waitingForFinalize,
      );
    });

    test('an oversized image is rejected before any grant is requested',
        () async {
      final gateway = _FakeCustomerPhotoGateway();
      final storageClient = _FakeCustomerPhotoStorageClient();
      final container = buildContainer(
        gateway: gateway,
        storageClient: storageClient,
        picker: _FakeCustomerPhotoPicker(
          result: smallPickedPhoto(bytes: 6 * 1024 * 1024),
        ),
      );

      final success = await container
          .read(customerPhotoUploadProvider.notifier)
          .pickAndUpload(source: CustomerPhotoPickSource.gallery);

      expect(success, isFalse);
      expect(container.read(customerPhotoUploadProvider).phase,
          CustomerPhotoUploadPhase.failed);
      expect(container.read(customerPhotoUploadProvider).errorMessage,
          contains('büyük'));
      expect(gateway.requestUploadGrantCalls, isEmpty);
    });

    test(
        'an unsupported (non-image) file is rejected before any grant is requested',
        () async {
      final gateway = _FakeCustomerPhotoGateway();
      final container = buildContainer(
        gateway: gateway,
        storageClient: _FakeCustomerPhotoStorageClient(),
        picker: _FakeCustomerPhotoPicker(
          result: PickedCustomerPhoto(
            bytes: Uint8List(1024),
            fileName: 'document.pdf',
            mimeType: null,
          ),
        ),
      );

      final success = await container
          .read(customerPhotoUploadProvider.notifier)
          .pickAndUpload(source: CustomerPhotoPickSource.gallery);

      expect(success, isFalse);
      expect(container.read(customerPhotoUploadProvider).phase,
          CustomerPhotoUploadPhase.failed);
      expect(container.read(customerPhotoUploadProvider).errorMessage,
          contains('desteklenmiyor'));
      expect(gateway.requestUploadGrantCalls, isEmpty);
    });

    test(
        'a duplicate near-simultaneous tap never creates two parallel grants/uploads',
        () async {
      final gateway = _FakeCustomerPhotoGateway(
        grantResult: CustomerPhotoUploadGrant(
          grantId: 'grant-1',
          objectPath: 'tenants/org-1/customerPhotos/customer-uid-1/grant-1',
          contentType: 'image/png',
          expiresAt: DateTime(2026, 8, 1, 12, 15),
        ),
      );
      final storageClient = _FakeCustomerPhotoStorageClient();
      final container = buildContainer(
        gateway: gateway,
        storageClient: storageClient,
        picker: _FakeCustomerPhotoPicker(result: smallPickedPhoto()),
      );
      final notifier = container.read(customerPhotoUploadProvider.notifier);

      final results = await Future.wait([
        notifier.pickAndUpload(source: CustomerPhotoPickSource.gallery),
        notifier.pickAndUpload(source: CustomerPhotoPickSource.gallery),
      ]);

      expect(results.where((r) => r).length, 1,
          reason: 'exactly one of the two calls actually proceeds');
      expect(gateway.requestUploadGrantCalls, hasLength(1));
      expect(storageClient.uploadCalls, hasLength(1));
    });

    test(
        'a resource-exhausted grant rejection maps to the locked max-10 message, distinct from a generic failure',
        () async {
      final gateway = _FakeCustomerPhotoGateway(
        grantError:
            const CustomerPhotoGatewayException('resource-exhausted', 'quota'),
      );
      final container = buildContainer(
        gateway: gateway,
        storageClient: _FakeCustomerPhotoStorageClient(),
        picker: _FakeCustomerPhotoPicker(result: smallPickedPhoto()),
      );

      final success = await container
          .read(customerPhotoUploadProvider.notifier)
          .pickAndUpload(source: CustomerPhotoPickSource.gallery);

      expect(success, isFalse);
      final state = container.read(customerPhotoUploadProvider);
      expect(state.limitReached, isTrue);
      expect(
          state.errorMessage, 'En fazla 10 profil fotoğrafı ekleyebilirsin.');
    });

    test('a generic grant rejection does not claim the limit was reached',
        () async {
      final gateway = _FakeCustomerPhotoGateway(
        grantError: const CustomerPhotoGatewayException('internal', 'boom'),
      );
      final container = buildContainer(
        gateway: gateway,
        storageClient: _FakeCustomerPhotoStorageClient(),
        picker: _FakeCustomerPhotoPicker(result: smallPickedPhoto()),
      );

      await container
          .read(customerPhotoUploadProvider.notifier)
          .pickAndUpload(source: CustomerPhotoPickSource.gallery);

      final state = container.read(customerPhotoUploadProvider);
      expect(state.limitReached, isFalse);
      expect(state.errorMessage, isNot(contains('10')));
    });

    test(
        'a Storage upload failure leaves the app recoverable — failed phase, not stuck busy',
        () async {
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
      final container = buildContainer(
        gateway: gateway,
        storageClient: storageClient,
        picker: _FakeCustomerPhotoPicker(result: smallPickedPhoto()),
      );

      final success = await container
          .read(customerPhotoUploadProvider.notifier)
          .pickAndUpload(source: CustomerPhotoPickSource.gallery);

      expect(success, isFalse);
      final state = container.read(customerPhotoUploadProvider);
      expect(state.phase, CustomerPhotoUploadPhase.failed);
      expect(state.isBusy, isFalse,
          reason: 'the app is not stuck — a new attempt can be made');
    });

    test(
        'gallery refresh eventually clears waitingForFinalize once the backend-created photo appears',
        () async {
      final gateway = _FakeCustomerPhotoGateway(
        grantResult: CustomerPhotoUploadGrant(
          grantId: 'grant-1',
          objectPath: 'tenants/org-1/customerPhotos/customer-uid-1/grant-1',
          contentType: 'image/png',
          expiresAt: DateTime(2026, 8, 1, 12, 15),
        ),
      );
      final container = buildContainer(
        gateway: gateway,
        storageClient: _FakeCustomerPhotoStorageClient(),
        picker: _FakeCustomerPhotoPicker(result: smallPickedPhoto()),
      );
      gateway.emitGallery([]);
      await container.read(customerPhotoGalleryProvider.future);

      await container
          .read(customerPhotoUploadProvider.notifier)
          .pickAndUpload(source: CustomerPhotoPickSource.gallery);
      expect(
        container.read(customerPhotoUploadProvider).phase,
        CustomerPhotoUploadPhase.waitingForFinalize,
      );

      // The backend "finalized" the upload — the gallery stream now shows
      // a photo whose id matches the grantId.
      gateway.emitGallery([samplePhoto(id: 'grant-1')]);
      await pumpEventQueue();

      expect(container.read(customerPhotoUploadProvider).phase,
          CustomerPhotoUploadPhase.idle);
      expect(
          container.read(customerPhotoUploadProvider).pendingGrantId, isNull);
    });
  });

  // =========================================================================
  // CR.1.2 — CustomerPhotoUploadNotifier.uploadPicked (already-picked
  // bytes, e.g. Step2PhotoStep's own local-preview flow — no picker call
  // inside this entry point).
  // =========================================================================

  group('CustomerPhotoUploadNotifier.uploadPicked', () {
    test('uploads already-picked bytes without ever calling the picker',
        () async {
      final gateway = _FakeCustomerPhotoGateway(
        grantResult: CustomerPhotoUploadGrant(
          grantId: 'grant-1',
          objectPath: 'tenants/org-1/customerPhotos/customer-uid-1/grant-1',
          contentType: 'image/png',
          expiresAt: DateTime(2026, 8, 1, 12, 15),
        ),
      );
      final storageClient = _FakeCustomerPhotoStorageClient();
      final picker = _FakeCustomerPhotoPicker(result: null);
      final container = buildContainer(
        gateway: gateway,
        storageClient: storageClient,
        picker: picker,
      );

      final success = await container
          .read(customerPhotoUploadProvider.notifier)
          .uploadPicked(picked: smallPickedPhoto());

      expect(success, isTrue);
      expect(picker.callCount, 0,
          reason: 'uploadPicked never invokes the picker itself');
      expect(storageClient.uploadCalls, hasLength(1));
    });

    test('forwards purpose to the gateway grant request', () async {
      final gateway = _FakeCustomerPhotoGateway(
        grantResult: CustomerPhotoUploadGrant(
          grantId: 'grant-1',
          objectPath: 'tenants/org-1/customerPhotos/customer-uid-1/grant-1',
          contentType: 'image/png',
          expiresAt: DateTime(2026, 8, 1, 12, 15),
        ),
      );
      final container = buildContainer(
        gateway: gateway,
        storageClient: _FakeCustomerPhotoStorageClient(),
        picker: _FakeCustomerPhotoPicker(result: null),
      );

      await container.read(customerPhotoUploadProvider.notifier).uploadPicked(
            picked: smallPickedPhoto(),
            purpose: 'profileOnboarding',
          );

      expect(
        gateway.requestUploadGrantCalls.single['purpose'],
        'profileOnboarding',
      );
    });

    test(
        'a duplicate near-simultaneous call never creates two parallel uploads',
        () async {
      final gateway = _FakeCustomerPhotoGateway(
        grantResult: CustomerPhotoUploadGrant(
          grantId: 'grant-1',
          objectPath: 'tenants/org-1/customerPhotos/customer-uid-1/grant-1',
          contentType: 'image/png',
          expiresAt: DateTime(2026, 8, 1, 12, 15),
        ),
      );
      final storageClient = _FakeCustomerPhotoStorageClient();
      final container = buildContainer(
        gateway: gateway,
        storageClient: storageClient,
        picker: _FakeCustomerPhotoPicker(result: null),
      );
      final notifier = container.read(customerPhotoUploadProvider.notifier);
      final picked = smallPickedPhoto();

      final results = await Future.wait([
        notifier.uploadPicked(picked: picked),
        notifier.uploadPicked(picked: picked),
      ]);

      expect(results.where((r) => r).length, 1);
      expect(gateway.requestUploadGrantCalls, hasLength(1));
      expect(storageClient.uploadCalls, hasLength(1));
    });
  });

  // =========================================================================
  // Storage Upload Control-Flow Diagnostic (2026-08-19) — a physical-device
  // test confirmed the Storage Emulator IS reachable yet
  // finalizeCustomerPhotoUpload never fires and no failure diagnostic
  // appears. Static audit of the control flow (below) found no defect —
  // these tests instead verify the new milestone-logging trail itself
  // fires in the right order, so the NEXT physical-device run has a real
  // breadcrumb trail to read instead of silence.
  // =========================================================================

  group('Storage upload control-flow diagnostic — milestone trail', () {
    test(
        'a successful upload emits every milestone in order: entered, '
        'picker completed, validation passed, grant requested, grant '
        'received, before uploadBytes, waiting-for-finalize entered', () async {
      final logger = _RecordingLoggingService();
      final gateway = _FakeCustomerPhotoGateway(
        grantResult: CustomerPhotoUploadGrant(
          grantId: 'grant-1',
          objectPath: 'tenants/org-1/customerPhotos/customer-uid-1/grant-1',
          contentType: 'image/png',
          expiresAt: DateTime(2026, 8, 1, 12, 15),
        ),
      );
      final storageClient = _FakeCustomerPhotoStorageClient();
      final container = buildContainer(
        gateway: gateway,
        storageClient: storageClient,
        picker: _FakeCustomerPhotoPicker(result: smallPickedPhoto()),
        loggingService: logger,
      );

      await container
          .read(customerPhotoUploadProvider.notifier)
          .pickAndUpload(source: CustomerPhotoPickSource.gallery);

      expect(logger.messages, [
        '[CustomerPhotoUpload] upload action entered',
        '[CustomerPhotoUpload] image picker completed',
        '[CustomerPhotoUpload] client validation passed',
        '[CustomerPhotoUpload] upload grant request started',
        '[CustomerPhotoUpload] upload grant received',
        '[CustomerPhotoUpload] immediately before CustomerPhotoStorageClient.uploadBytes',
        '[CustomerPhotoUpload] waiting-for-finalize phase entered',
      ]);
    });

    test(
        'a Storage upload failure emits every milestone up to "before '
        'uploadBytes" but never "waiting-for-finalize entered"', () async {
      final logger = _RecordingLoggingService();
      final gateway = _FakeCustomerPhotoGateway(
        grantResult: CustomerPhotoUploadGrant(
          grantId: 'grant-1',
          objectPath: 'tenants/org-1/customerPhotos/customer-uid-1/grant-1',
          contentType: 'image/png',
          expiresAt: DateTime(2026, 8, 1, 12, 15),
        ),
      );
      final storageClient = _FakeCustomerPhotoStorageClient(
        uploadError: const CustomerPhotoStorageException('unknown', 'boom'),
      );
      final container = buildContainer(
        gateway: gateway,
        storageClient: storageClient,
        picker: _FakeCustomerPhotoPicker(result: smallPickedPhoto()),
        loggingService: logger,
      );

      await container
          .read(customerPhotoUploadProvider.notifier)
          .pickAndUpload(source: CustomerPhotoPickSource.gallery);

      expect(
        logger.messages,
        contains(
          '[CustomerPhotoUpload] immediately before CustomerPhotoStorageClient.uploadBytes',
        ),
      );
      expect(
        logger.messages,
        isNot(contains(
            '[CustomerPhotoUpload] waiting-for-finalize phase entered')),
        reason: 'a thrown uploadBytes never reaches the waiting-for-finalize '
            'transition — proves this control-flow path, not just the '
            'happy path, is covered.',
      );
    });

    test(
        'a cancelled pick emits "upload action entered" and a cancelled '
        '"image picker completed", then nothing further', () async {
      final logger = _RecordingLoggingService();
      final gateway = _FakeCustomerPhotoGateway();
      final container = buildContainer(
        gateway: gateway,
        storageClient: _FakeCustomerPhotoStorageClient(),
        picker: _FakeCustomerPhotoPicker(result: null),
        loggingService: logger,
      );

      await container
          .read(customerPhotoUploadProvider.notifier)
          .pickAndUpload(source: CustomerPhotoPickSource.gallery);

      expect(logger.messages, [
        '[CustomerPhotoUpload] upload action entered',
        '[CustomerPhotoUpload] image picker completed',
      ]);
      expect(gateway.requestUploadGrantCalls, isEmpty);
    });

    test(
        '"customerPhotos document observed" is logged exactly when the '
        'gallery listener actually clears waitingForFinalize', () async {
      final logger = _RecordingLoggingService();
      final gateway = _FakeCustomerPhotoGateway(
        grantResult: CustomerPhotoUploadGrant(
          grantId: 'grant-1',
          objectPath: 'tenants/org-1/customerPhotos/customer-uid-1/grant-1',
          contentType: 'image/png',
          expiresAt: DateTime(2026, 8, 1, 12, 15),
        ),
      );
      final container = buildContainer(
        gateway: gateway,
        storageClient: _FakeCustomerPhotoStorageClient(),
        picker: _FakeCustomerPhotoPicker(result: smallPickedPhoto()),
        loggingService: logger,
      );
      gateway.emitGallery([]);
      await container.read(customerPhotoGalleryProvider.future);

      await container
          .read(customerPhotoUploadProvider.notifier)
          .pickAndUpload(source: CustomerPhotoPickSource.gallery);
      expect(
        logger.messages,
        isNot(
            contains('[CustomerPhotoUpload] customerPhotos document observed')),
        reason: 'not yet — finalize has not happened',
      );

      gateway.emitGallery([samplePhoto(id: 'grant-1')]);
      await pumpEventQueue();

      expect(
        logger.messages,
        contains('[CustomerPhotoUpload] customerPhotos document observed'),
      );
    });
  });

  // =========================================================================
  // Gateway plumbing — selectProfilePhoto (P.4.3B wires this into the UI;
  // the data-layer integration is proven now, per the task's own scope note)
  // =========================================================================

  group('CustomerPhotoGateway.selectProfilePhoto', () {
    test('calls through with the exact organizationId/photoId given', () async {
      final gateway = _FakeCustomerPhotoGateway();
      await gateway.selectProfilePhoto(
          organizationId: 'org-1', photoId: 'photo-1');

      expect(gateway.selectProfilePhotoCalls, hasLength(1));
      expect(gateway.selectProfilePhotoCalls.single, {
        'organizationId': 'org-1',
        'photoId': 'photo-1',
      });
    });

    test(
        'propagates a CustomerPhotoGatewayException from the backend unchanged',
        () async {
      final gateway = _FakeCustomerPhotoGateway(
        selectError: const CustomerPhotoGatewayException(
            'failed-precondition', 'not approved'),
      );

      await expectLater(
        gateway.selectProfilePhoto(organizationId: 'org-1', photoId: 'photo-1'),
        throwsA(isA<CustomerPhotoGatewayException>()),
      );
    });
  });

  // =========================================================================
  // CONFIG / GATEWAY — structural guards
  // =========================================================================

  group('structural guards', () {
    test(
        'the customer photo gateway never issues a direct Firestore write to customerPhotos — reads only',
        () {
      final source =
          File('lib/features/customer_photos/data/customer_photo_gateway.dart')
              .readAsStringSync();
      // Firestore write method names — none may appear in a file whose
      // ONE Firestore interaction is `watchGallery`'s `.snapshots()` read.
      for (final writeMethod in ['.set(', '.update(', '.delete(', '.add(']) {
        expect(source.contains(writeMethod), isFalse,
            reason:
                '$writeMethod must never appear — client never writes customerPhotos directly');
      }
    });

    test(
        'no profilePicturePath references anywhere in the customer photo client code',
        () {
      final files = [
        'lib/features/customer_photos/data/customer_photo_gateway.dart',
        'lib/features/customer_photos/data/customer_photo_storage_client.dart',
        'lib/features/customer_photos/presentation/providers/customer_photo_upload_provider.dart',
        'lib/features/customer_photos/presentation/providers/customer_photo_providers.dart',
      ];
      for (final path in files) {
        final codeOnly = _stripCommentLines(File(path).readAsStringSync());
        expect(codeOnly.contains('profilePicturePath'), isFalse,
            reason: '$path must never reference profilePicturePath in code');
      }
    });

    test(
        'no public-projection (customerPublicProfiles) reference outside the one authorized read in customer_photo_gateway.dart',
        () {
      // P.4.3B added ONE authorized, read-only reference —
      // `watchSelectedProfilePhotoRef`'s `.snapshots()` — the gateway's
      // own first structural guard above (no `.set(`/`.update(`/
      // `.delete(`/`.add(` anywhere in this file) already proves it can
      // never be a write. Every OTHER customer-photo client file must
      // still never reference this collection at all — reading the
      // customer's own public selection is this gateway's job alone.
      final otherFiles = [
        'lib/features/customer_photos/data/customer_photo_storage_client.dart',
        'lib/features/customer_photos/presentation/providers/customer_photo_upload_provider.dart',
        'lib/features/customer_photos/presentation/providers/customer_photo_providers.dart',
      ];
      for (final path in otherFiles) {
        final codeOnly = _stripCommentLines(File(path).readAsStringSync());
        expect(codeOnly.contains('customerPublicProfiles'), isFalse,
            reason:
                '$path must never reference customerPublicProfiles in code');
      }

      final gatewayCode = _stripCommentLines(File(
        'lib/features/customer_photos/data/customer_photo_gateway.dart',
      ).readAsStringSync());
      expect(
        'customerPublicProfiles'.allMatches(gatewayCode).length,
        1,
        reason:
            'exactly one reference — watchSelectedProfilePhotoRef\'s own read '
            '— never more than one code site touching this collection',
      );
    });

    test(
        'the shared upload path never imports dart:io — Web must stay supported',
        () {
      final files = [
        'lib/features/customer_photos/data/customer_photo_gateway.dart',
        'lib/features/customer_photos/data/customer_photo_storage_client.dart',
        'lib/features/customer_photos/data/customer_photo_picker.dart',
        'lib/features/customer_photos/presentation/providers/customer_photo_upload_provider.dart',
        'lib/features/customer_photos/presentation/providers/customer_photo_providers.dart',
      ];
      final dartIoImport =
          RegExp('''^import\\s+['"]dart:io['"]''', multiLine: true);
      for (final path in files) {
        final source = File(path).readAsStringSync();
        expect(dartIoImport.hasMatch(source), isFalse,
            reason: '$path must not import dart:io');
      }
    });
  });
}

String _stripCommentLines(String source) {
  return source.split('\n').where((line) {
    final trimmed = line.trimLeft();
    return !trimmed.startsWith('//') &&
        !trimmed.startsWith('///') &&
        !trimmed.startsWith('*') &&
        !trimmed.startsWith('/*');
  }).join('\n');
}

class _FakeCustomerPhotoGateway implements CustomerPhotoGateway {
  _FakeCustomerPhotoGateway(
      {this.grantResult, this.grantError, this.selectError});

  final CustomerPhotoUploadGrant? grantResult;
  final CustomerPhotoGatewayException? grantError;
  final CustomerPhotoGatewayException? selectError;

  final List<Map<String, dynamic>> requestUploadGrantCalls = [];
  final List<Map<String, dynamic>> selectProfilePhotoCalls = [];
  final List<Map<String, dynamic>> watchGalleryCalls = [];

  List<CustomerPhoto> _photos = [];
  final List<StreamController<List<CustomerPhoto>>> _controllers = [];

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
    watchGalleryCalls
        .add({'organizationId': organizationId, 'customerId': customerId});
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
  }) async {
    selectProfilePhotoCalls
        .add({'organizationId': organizationId, 'photoId': photoId});
    if (selectError != null) throw selectError!;
  }

  @override
  Stream<String?> watchSelectedProfilePhotoRef({
    required String organizationId,
    required String customerId,
  }) =>
      Stream.value(null);
}

class _FakeCustomerPhotoStorageClient implements CustomerPhotoStorageClient {
  _FakeCustomerPhotoStorageClient({this.uploadError});

  final CustomerPhotoStorageException? uploadError;
  final List<Map<String, dynamic>> uploadCalls = [];

  @override
  Future<void> uploadBytes({
    required String objectPath,
    required Uint8List bytes,
    required String contentType,
  }) async {
    uploadCalls.add({'objectPath': objectPath, 'contentType': contentType});
    if (uploadError != null) throw uploadError!;
  }

  @override
  Future<Uint8List?> downloadBytes(String objectPath) async => null;
}

/// Captures every `log(...)` call's message, in order — enough to assert
/// on the milestone trail without depending on `LogRedactor`'s own
/// rendering details, which are already covered elsewhere.
class _RecordingLoggingService implements LoggingService {
  final List<String> messages = [];
  final List<LogLevel> levels = [];

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
  }
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
