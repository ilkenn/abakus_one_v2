import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/auth/presentation/screens/login_screen.dart';
import 'package:abakus_one_v2/features/customer_photos/data/customer_photo_gateway.dart';
import 'package:abakus_one_v2/features/customer_photos/data/customer_photo_storage_client.dart';
import 'package:abakus_one_v2/features/customer_photos/presentation/providers/customer_photo_providers.dart';
import 'package:abakus_one_v2/features/profile/data/customer_identity_gateway.dart';
import 'package:abakus_one_v2/features/profile/domain/models/customer_identity.dart';
import 'package:abakus_one_v2/features/profile/presentation/providers/customer_identity_provider.dart';
import 'package:abakus_one_v2/features/profile/presentation/widgets/profile_hero_card.dart';
import 'package:abakus_one_v2/shared/models/customer_photo.dart';
import 'package:abakus_one_v2/shared/models/customer_photo_status.dart';

/// P.4.3B — the Profile hero's identity now comes from real
/// `customers/{uid}` data (via [CustomerIdentityGateway]) and its photo
/// priority from [CustomerPhotoGateway]'s gallery/selection streams —
/// this suite replaces the old phone-number-primary-identity assertions
/// (`profile.name` was the phone number) with real-identity/photo-priority
/// coverage. `authProvider` is still the guest/authenticated switch,
/// unchanged from before this task.
class _SignedInNotifier extends AuthNotifier {
  _SignedInNotifier(this.uid, this.phoneNumber);
  final String uid;
  final String phoneNumber;

  @override
  AuthState build() => AuthState(
        isAuthenticated: true,
        isGuest: false,
        session: AuthSession(
          uid: uid,
          phoneNumber: phoneNumber,
          createdAt: DateTime(2026, 1, 1),
          expiresAt: DateTime(2026, 12, 31),
        ),
      );
}

class _SignedOutNotifier extends AuthNotifier {
  @override
  AuthState build() => const AuthState(isAuthenticated: false, isGuest: false);
}

void main() {
  const defaultIdentity = CustomerIdentity(
    firstName: 'İlken',
    lastName: 'Parlakbudak',
    email: 'ilken@example.com',
    occupationStatus: CustomerOccupationStatus.working,
    workplaceName: 'Abaküs Bowl',
  );

  // A real, minimal, valid 1x1 PNG — `Image.memory` genuinely decodes
  // these bytes (a zeroed buffer throws "Invalid image data" and fails
  // the test via `FlutterError.onError`).
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

  CustomerPhoto photo({
    required String id,
    required CustomerPhotoStatus status,
    DateTime? uploadedAt,
    bool isSelectedAsProfilePhoto = false,
  }) {
    return CustomerPhoto(
      id: id,
      customerId: 'uid-1',
      organizationId: 'org-1',
      photoRef: 'tenants/org-1/customerPhotos/uid-1/$id',
      status: status,
      isSelectedAsProfilePhoto: isSelectedAsProfilePhoto,
      uploadedAt: uploadedAt ?? DateTime(2026, 8, 1),
      revision: 1,
    );
  }

  Future<void> pumpHero(
    WidgetTester tester, {
    required AuthNotifier Function() authNotifierBuilder,
    CustomerIdentityGateway? identityGateway,
    CustomerPhotoGateway? photoGateway,
    CustomerPhotoStorageClient? storageClient,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(authNotifierBuilder),
          customerIdentityGatewayProvider.overrideWithValue(
            identityGateway ??
                _FakeCustomerIdentityGateway(identity: defaultIdentity),
          ),
          customerPhotoGatewayProvider.overrideWithValue(
            photoGateway ?? _FakeCustomerPhotoGateway(),
          ),
          customerPhotoStorageClientProvider.overrideWithValue(
            storageClient ?? _FakeCustomerPhotoStorageClient(),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: ProfileHeroCard())),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('canonical identity', () {
    testWidgets('shows the real full name (firstName + lastName)',
        (tester) async {
      await pumpHero(
        tester,
        authNotifierBuilder: () => _SignedInNotifier('uid-1', '+905551112233'),
      );

      expect(find.byKey(const Key('profileHeroFullName')), findsOneWidget);
      expect(find.text('İlken Parlakbudak'), findsOneWidget);
    });

    testWidgets('shows the real email', (tester) async {
      await pumpHero(
        tester,
        authNotifierBuilder: () => _SignedInNotifier('uid-1', '+905551112233'),
      );

      expect(find.byKey(const Key('profileHeroEmail')), findsOneWidget);
      expect(find.text('ilken@example.com'), findsOneWidget);
    });

    testWidgets('working customer shows workplaceName', (tester) async {
      await pumpHero(
        tester,
        authNotifierBuilder: () => _SignedInNotifier('uid-1', '+905551112233'),
        identityGateway: _FakeCustomerIdentityGateway(
          identity: const CustomerIdentity(
            firstName: 'Ahmet',
            lastName: 'Kaya',
            email: 'ahmet.kaya@example.com',
            occupationStatus: CustomerOccupationStatus.working,
            workplaceName: 'Abaküs Merkez Şube',
          ),
        ),
      );

      expect(find.text('Abaküs Merkez Şube'), findsOneWidget);
    });

    testWidgets('student customer shows educationalInstitutionName',
        (tester) async {
      await pumpHero(
        tester,
        authNotifierBuilder: () => _SignedInNotifier('uid-1', '+905551112233'),
        identityGateway: _FakeCustomerIdentityGateway(
          identity: const CustomerIdentity(
            firstName: 'Ahmet',
            lastName: 'Yılmaz',
            email: 'ahmet@example.com',
            occupationStatus: CustomerOccupationStatus.student,
            educationalInstitutionName: 'Kabataş Erkek Lisesi',
          ),
        ),
      );

      expect(find.text('Kabataş Erkek Lisesi'), findsOneWidget);
    });

    testWidgets(
        'occupationStatus other never invents a workplace/institution line',
        (tester) async {
      await pumpHero(
        tester,
        authNotifierBuilder: () => _SignedInNotifier('uid-1', '+905551112233'),
        identityGateway: _FakeCustomerIdentityGateway(
          identity: const CustomerIdentity(
            firstName: 'Ahmet',
            lastName: 'Demir',
            email: 'ahmet.demir@example.com',
            occupationStatus: CustomerOccupationStatus.other,
          ),
        ),
      );

      expect(
          find.byKey(const Key('profileHeroWorkplaceOrSchool')), findsNothing);
    });

    testWidgets('phone number is never shown as the primary identity',
        (tester) async {
      await pumpHero(
        tester,
        authNotifierBuilder: () => _SignedInNotifier('uid-1', '+905551112233'),
      );

      expect(find.text('+905551112233'), findsNothing);
    });

    testWidgets('no fake Ahmet Yılmaz / fake email fallback ever appears',
        (tester) async {
      await pumpHero(
        tester,
        authNotifierBuilder: () => _SignedInNotifier('uid-1', '+905551112233'),
      );

      expect(find.text('Ahmet Yılmaz'), findsNothing);
      expect(find.text('ahmet.yilmaz@abakusbowl.com'), findsNothing);
    });
  });

  group('photo hero priority', () {
    testWidgets('no photos at all -> initials avatar', (tester) async {
      await pumpHero(
        tester,
        authNotifierBuilder: () => _SignedInNotifier('uid-1', '+905551112233'),
      );

      expect(
          find.byKey(const Key('profileHeroInitialsAvatar')), findsOneWidget);
      expect(find.text('İP'), findsOneWidget);
      expect(find.byKey(const Key('profileHeroPhotoImage')), findsNothing);
      expect(find.byKey(const Key('profileHeroPendingBadge')), findsNothing);
    });

    testWidgets(
        'an approved + publicly-selected photo renders as the hero photo — restart-safe (derives purely from providers, no prior widget state)',
        (tester) async {
      final approved = photo(id: 'p1', status: CustomerPhotoStatus.approved);
      final bytes = validPngBytes();
      await pumpHero(
        tester,
        authNotifierBuilder: () => _SignedInNotifier('uid-1', '+905551112233'),
        photoGateway: _FakeCustomerPhotoGateway(
          galleryPhotos: [approved],
          selectedProfilePhotoRef: approved.photoRef,
        ),
        storageClient:
            _FakeCustomerPhotoStorageClient({approved.photoRef: bytes}),
      );

      expect(find.byKey(const Key('profileHeroPhotoImage')), findsOneWidget);
      expect(find.byKey(const Key('profileHeroInitialsAvatar')), findsNothing);
      expect(find.byKey(const Key('profileHeroPendingBadge')), findsNothing);
    });

    testWidgets(
        'a pendingReview photo is shown as the owner-private hero with "Onay Bekliyor"',
        (tester) async {
      final pending =
          photo(id: 'p1', status: CustomerPhotoStatus.pendingReview);
      final bytes = validPngBytes();
      await pumpHero(
        tester,
        authNotifierBuilder: () => _SignedInNotifier('uid-1', '+905551112233'),
        photoGateway: _FakeCustomerPhotoGateway(galleryPhotos: [pending]),
        storageClient:
            _FakeCustomerPhotoStorageClient({pending.photoRef: bytes}),
      );

      expect(find.byKey(const Key('profileHeroPhotoImage')), findsOneWidget);
      expect(find.byKey(const Key('profileHeroPendingBadge')), findsOneWidget);
      expect(find.text('Onay Bekliyor'), findsOneWidget);
    });

    testWidgets(
        'an underReview photo is shown as the owner-private hero with "İnceleniyor"',
        (tester) async {
      final underReview =
          photo(id: 'p1', status: CustomerPhotoStatus.underReview);
      final bytes = validPngBytes();
      await pumpHero(
        tester,
        authNotifierBuilder: () => _SignedInNotifier('uid-1', '+905551112233'),
        photoGateway: _FakeCustomerPhotoGateway(galleryPhotos: [underReview]),
        storageClient:
            _FakeCustomerPhotoStorageClient({underReview.photoRef: bytes}),
      );

      expect(find.byKey(const Key('profileHeroPhotoImage')), findsOneWidget);
      expect(find.byKey(const Key('profileHeroPendingBadge')), findsOneWidget);
      expect(find.text('İnceleniyor'), findsOneWidget);
    });

    testWidgets('a rejected photo is never shown as the hero photo',
        (tester) async {
      final rejected = photo(id: 'p1', status: CustomerPhotoStatus.rejected);
      await pumpHero(
        tester,
        authNotifierBuilder: () => _SignedInNotifier('uid-1', '+905551112233'),
        photoGateway: _FakeCustomerPhotoGateway(
          galleryPhotos: [rejected],
          selectedProfilePhotoRef: rejected.photoRef,
        ),
      );

      expect(
          find.byKey(const Key('profileHeroInitialsAvatar')), findsOneWidget);
      expect(find.byKey(const Key('profileHeroPhotoImage')), findsNothing);
    });

    testWidgets('a removed photo is never shown as the hero photo',
        (tester) async {
      final removed = photo(id: 'p1', status: CustomerPhotoStatus.removed);
      await pumpHero(
        tester,
        authNotifierBuilder: () => _SignedInNotifier('uid-1', '+905551112233'),
        photoGateway: _FakeCustomerPhotoGateway(
          galleryPhotos: [removed],
          selectedProfilePhotoRef: removed.photoRef,
        ),
      );

      expect(
          find.byKey(const Key('profileHeroInitialsAvatar')), findsOneWidget);
      expect(find.byKey(const Key('profileHeroPhotoImage')), findsNothing);
    });

    testWidgets(
        'when several pending/underReview photos exist, the newest wins and ONLY its bytes are downloaded',
        (tester) async {
      final older = photo(
        id: 'older',
        status: CustomerPhotoStatus.pendingReview,
        uploadedAt: DateTime(2026, 8, 1),
      );
      final newest = photo(
        id: 'newest',
        status: CustomerPhotoStatus.underReview,
        uploadedAt: DateTime(2026, 8, 5),
      );
      final storageClient = _FakeCustomerPhotoStorageClient({
        older.photoRef: validPngBytes(),
        newest.photoRef: validPngBytes(),
      });
      await pumpHero(
        tester,
        authNotifierBuilder: () => _SignedInNotifier('uid-1', '+905551112233'),
        photoGateway: _FakeCustomerPhotoGateway(galleryPhotos: [older, newest]),
        storageClient: storageClient,
      );

      expect(find.text('İnceleniyor'), findsOneWidget,
          reason: 'the newest (underReview) photo must win, not the older '
              'pendingReview one');
      expect(storageClient.downloadCalls, [newest.photoRef],
          reason: 'only the resolved hero photo\'s bytes are ever downloaded — '
              'never the whole private gallery');
    });

    testWidgets(
        'a newly-uploaded pending photo overrides an already-approved-and-selected photo for the owner\'s own hero',
        (tester) async {
      final approvedSelected =
          photo(id: 'approved-1', status: CustomerPhotoStatus.approved);
      final pending = photo(
        id: 'pending-1',
        status: CustomerPhotoStatus.pendingReview,
        uploadedAt: DateTime(2026, 8, 10),
      );
      final storageClient = _FakeCustomerPhotoStorageClient({
        approvedSelected.photoRef: validPngBytes(),
        pending.photoRef: validPngBytes(),
      });
      await pumpHero(
        tester,
        authNotifierBuilder: () => _SignedInNotifier('uid-1', '+905551112233'),
        photoGateway: _FakeCustomerPhotoGateway(
          galleryPhotos: [approvedSelected, pending],
          selectedProfilePhotoRef: approvedSelected.photoRef,
        ),
        storageClient: storageClient,
      );

      expect(find.byKey(const Key('profileHeroPendingBadge')), findsOneWidget);
      expect(find.text('Onay Bekliyor'), findsOneWidget);
      expect(storageClient.downloadCalls, [pending.photoRef]);
    });

    testWidgets(
        'the public canonical selection (selectedProfilePhotoRef) remains the sole authority — isSelectedAsProfilePhoto alone never substitutes',
        (tester) async {
      final approvedButNotProjected = photo(
        id: 'p1',
        status: CustomerPhotoStatus.approved,
        isSelectedAsProfilePhoto: true,
      );
      await pumpHero(
        tester,
        authNotifierBuilder: () => _SignedInNotifier('uid-1', '+905551112233'),
        photoGateway: _FakeCustomerPhotoGateway(
          galleryPhotos: [approvedButNotProjected],
          selectedProfilePhotoRef: null,
        ),
      );

      expect(find.byKey(const Key('profileHeroInitialsAvatar')), findsOneWidget,
          reason: 'without a matching customerPublicProfiles projection ref, '
              'the photo must never be treated as the public selection');
    });
  });

  group('loading / error / unavailable states', () {
    testWidgets(
        'while the identity is still loading, a stable skeleton shows — never a fabricated name',
        (tester) async {
      final neverEmits = StreamController<CustomerIdentity?>();
      addTearDown(neverEmits.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(
                () => _SignedInNotifier('uid-1', '+905551112233')),
            customerIdentityGatewayProvider.overrideWithValue(
              _FakeCustomerIdentityGateway(stream: neverEmits.stream),
            ),
            customerPhotoGatewayProvider
                .overrideWithValue(_FakeCustomerPhotoGateway()),
            customerPhotoStorageClientProvider
                .overrideWithValue(_FakeCustomerPhotoStorageClient({})),
          ],
          child: const MaterialApp(home: Scaffold(body: ProfileHeroCard())),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('profileHeroSkeleton')), findsOneWidget);
      expect(find.text('Ahmet Yılmaz'), findsNothing);
      expect(find.byKey(const Key('profileHeroFullName')), findsNothing);
    });

    testWidgets(
        'an error reading the identity shows a neutral unavailable state — never a fabricated name',
        (tester) async {
      await pumpHero(
        tester,
        authNotifierBuilder: () => _SignedInNotifier('uid-1', '+905551112233'),
        identityGateway: _FakeCustomerIdentityGateway(
          stream: Stream<CustomerIdentity?>.error(Exception('boom')),
        ),
      );

      expect(find.byKey(const Key('profileHeroUnavailable')), findsOneWidget);
      expect(
          find.byKey(const Key('profileHeroUnavailableText')), findsOneWidget);
      expect(find.byKey(const Key('profileHeroFullName')), findsNothing);
      expect(find.text('Ahmet Yılmaz'), findsNothing);
    });

    testWidgets(
        'a missing customers/{uid} document shows the same neutral unavailable state',
        (tester) async {
      await pumpHero(
        tester,
        authNotifierBuilder: () => _SignedInNotifier('uid-1', '+905551112233'),
        identityGateway: _FakeCustomerIdentityGateway(identity: null),
      );

      expect(find.byKey(const Key('profileHeroUnavailable')), findsOneWidget);
      expect(find.byKey(const Key('profileHeroFullName')), findsNothing);
    });
  });

  group('misafir (guest) — unchanged', () {
    testWidgets('sahte kimlik gostermez, giris yap CTAsi sunar', (
      tester,
    ) async {
      await pumpHero(
        tester,
        authNotifierBuilder: () => _SignedOutNotifier(),
      );

      expect(find.text('Ahmet Yılmaz'), findsNothing);
      expect(find.text('ahmet.yilmaz@abakusbowl.com'), findsNothing);
      expect(find.textContaining('user_123'), findsNothing);
      expect(find.text('Hesabına Giriş Yap'), findsOneWidget);
    });

    testWidgets('dokununca gercek LoginScreen acilir', (tester) async {
      await pumpHero(
        tester,
        authNotifierBuilder: () => _SignedOutNotifier(),
      );

      await tester.tap(find.text('Hesabına Giriş Yap'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });
}

class _FakeCustomerIdentityGateway implements CustomerIdentityGateway {
  _FakeCustomerIdentityGateway({
    CustomerIdentity? identity,
    Stream<CustomerIdentity?>? stream,
  }) : _stream = stream ?? Stream.value(identity);

  final Stream<CustomerIdentity?> _stream;

  @override
  Stream<CustomerIdentity?> watchOwnIdentity({required String uid}) => _stream;
}

class _FakeCustomerPhotoGateway implements CustomerPhotoGateway {
  _FakeCustomerPhotoGateway({
    List<CustomerPhoto> galleryPhotos = const [],
    String? selectedProfilePhotoRef,
  })  : _galleryPhotos = galleryPhotos,
        _selectedProfilePhotoRef = selectedProfilePhotoRef;

  final List<CustomerPhoto> _galleryPhotos;
  final String? _selectedProfilePhotoRef;

  @override
  Stream<List<CustomerPhoto>> watchGallery({
    required String organizationId,
    required String customerId,
  }) =>
      Stream.value(_galleryPhotos);

  @override
  Future<CustomerPhotoUploadGrant> requestUploadGrant({
    required String organizationId,
    required String contentType,
    String? purpose,
  }) =>
      throw UnimplementedError('not exercised by ProfileHeroCard');

  @override
  Future<void> selectProfilePhoto({
    required String organizationId,
    required String photoId,
  }) =>
      throw UnimplementedError('not exercised by ProfileHeroCard');

  @override
  Stream<String?> watchSelectedProfilePhotoRef({
    required String organizationId,
    required String customerId,
  }) =>
      Stream.value(_selectedProfilePhotoRef);
}

class _FakeCustomerPhotoStorageClient implements CustomerPhotoStorageClient {
  _FakeCustomerPhotoStorageClient([this._bytesByPath = const {}]);

  final Map<String, Uint8List> _bytesByPath;
  final List<String> downloadCalls = [];

  @override
  Future<void> uploadBytes({
    required String objectPath,
    required Uint8List bytes,
    required String contentType,
  }) =>
      throw UnimplementedError('not exercised by ProfileHeroCard');

  @override
  Future<Uint8List?> downloadBytes(String objectPath) async {
    downloadCalls.add(objectPath);
    return _bytesByPath[objectPath];
  }
}
