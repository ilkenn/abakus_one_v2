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
import 'package:abakus_one_v2/features/profile/presentation/screens/customer_photo_management_screen.dart';
import 'package:abakus_one_v2/shared/models/customer_photo.dart';
import 'package:abakus_one_v2/shared/models/customer_photo_status.dart';

/// Profile P.4.3A — widget-level coverage of "Profil Fotoğraflarım":
/// loading/empty/data states, the 10/10 add-button disable, and the
/// source-picker sheet actually invoking the picker with the right source.
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
    required String id,
    CustomerPhotoStatus status = CustomerPhotoStatus.pendingReview,
    String? rejectionReason,
  }) {
    return CustomerPhoto(
      id: id,
      customerId: 'customer-uid-1',
      organizationId: 'org-1',
      photoRef: 'tenants/org-1/customerPhotos/customer-uid-1/$id',
      status: status,
      uploadedAt: DateTime(2026, 8, 1),
      rejectionReason: rejectionReason,
      revision: 1,
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    required _FakeCustomerPhotoGateway gateway,
    _FakeCustomerPhotoPicker? picker,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider
              .overrideWith(() => SeededAuthNotifier(authenticatedState())),
          customerPhotoGatewayProvider.overrideWithValue(gateway),
          customerPhotoStorageClientProvider.overrideWithValue(
            _NullCustomerPhotoStorageClient(),
          ),
          customerPhotoPickerProvider.overrideWithValue(
            picker ?? _FakeCustomerPhotoPicker(result: null),
          ),
        ],
        child: const MaterialApp(home: CustomerPhotoManagementScreen()),
      ),
    );
  }

  testWidgets('loading — shows a loading indicator before the first snapshot',
      (tester) async {
    final gateway = _FakeCustomerPhotoGateway();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider
              .overrideWith(() => SeededAuthNotifier(authenticatedState())),
          customerPhotoGatewayProvider.overrideWithValue(gateway),
          customerPhotoStorageClientProvider.overrideWithValue(
            _NullCustomerPhotoStorageClient(),
          ),
          customerPhotoPickerProvider.overrideWithValue(
            _FakeCustomerPhotoPicker(result: null),
          ),
        ],
        child: const MaterialApp(home: CustomerPhotoManagementScreen()),
      ),
    );
    // Deliberately not settling and never calling emitGallery — the fake
    // gateway's stream has not produced its first event yet, so the
    // provider is still genuinely AsyncLoading at this exact point.
    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });

  testWidgets('empty — shows the empty state with an add-photo action',
      (tester) async {
    final gateway = _FakeCustomerPhotoGateway();
    await pumpScreen(tester, gateway: gateway);
    gateway.emitGallery([]);
    await tester.pumpAndSettle();

    expect(find.text('Henüz bir profil fotoğrafı eklemedin.'), findsOneWidget);
    expect(find.text('0 / 10'), findsOneWidget);
  });

  testWidgets(
      'data — pendingReview/underReview/approved/rejected each show their own customer-safe label',
      (tester) async {
    final gateway = _FakeCustomerPhotoGateway();
    await pumpScreen(tester, gateway: gateway);
    gateway.emitGallery([
      samplePhoto(id: 'p1', status: CustomerPhotoStatus.pendingReview),
      samplePhoto(id: 'p2', status: CustomerPhotoStatus.underReview),
      samplePhoto(id: 'p3', status: CustomerPhotoStatus.approved),
      samplePhoto(
          id: 'p4',
          status: CustomerPhotoStatus.rejected,
          rejectionReason: 'bulanık'),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Onay Bekliyor'), findsOneWidget);
    expect(find.text('İnceleniyor'), findsOneWidget);
    expect(find.text('Onaylandı'), findsOneWidget);
    expect(find.text('Onaylanmadı'), findsOneWidget);
    expect(find.text('bulanık'), findsOneWidget);
    expect(find.text('3 / 10'), findsOneWidget,
        reason: 'rejected does not count toward the active total');
  });

  testWidgets('10/10 active photos disables the "Fotoğraf Ekle" button',
      (tester) async {
    final gateway = _FakeCustomerPhotoGateway();
    await pumpScreen(tester, gateway: gateway);
    gateway.emitGallery([
      for (var i = 0; i < 10; i++)
        samplePhoto(id: 'p$i', status: CustomerPhotoStatus.approved),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('10 / 10'), findsOneWidget);
    expect(find.text('En fazla 10 profil fotoğrafı ekleyebilirsin.'),
        findsOneWidget);
    final button = tester.widget<ElevatedButton>(
      find.byKey(const Key('customerPhotoAddButton')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets(
      'under 10, tapping "Fotoğraf Ekle" then "Galeriden Seç" invokes the picker with the gallery source',
      (tester) async {
    final gateway = _FakeCustomerPhotoGateway();
    final picker = _FakeCustomerPhotoPicker(
        result: null); // cancelled — simplest path to assert the call itself
    await pumpScreen(tester, gateway: gateway, picker: picker);
    gateway.emitGallery([]);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('customerPhotoAddButton')));
    await tester.pumpAndSettle();
    expect(find.text('Galeriden Seç'), findsOneWidget);
    expect(find.text('Kameradan Çek'), findsOneWidget);

    await tester.tap(find.text('Galeriden Seç'));
    await tester.pumpAndSettle();

    expect(picker.callCount, 1);
    expect(picker.lastSource, CustomerPhotoPickSource.gallery);
  });

  testWidgets('error — gallery load failure shows a retry-capable error state',
      (tester) async {
    final gateway = _FakeCustomerPhotoGateway();
    await pumpScreen(tester, gateway: gateway);
    gateway.emitError(Exception('network down'));
    await tester.pumpAndSettle();

    expect(find.text('Fotoğrafların yüklenemedi. Lütfen tekrar dene.'),
        findsOneWidget);
    expect(find.text('Tekrar Dene'), findsOneWidget);
  });
}

class _NullCustomerPhotoStorageClient implements CustomerPhotoStorageClient {
  @override
  Future<void> uploadBytes({
    required String objectPath,
    required Uint8List bytes,
    required String contentType,
  }) async {}

  @override
  Future<Uint8List?> downloadBytes(String objectPath) async => null;
}

class _FakeCustomerPhotoGateway implements CustomerPhotoGateway {
  List<CustomerPhoto> _photos = [];
  final List<StreamController<List<CustomerPhoto>>> _controllers = [];

  void emitGallery(List<CustomerPhoto> photos) {
    _photos = photos;
    for (final controller in _controllers) {
      if (!controller.isClosed) controller.add(photos);
    }
  }

  void emitError(Object error) {
    for (final controller in _controllers) {
      if (!controller.isClosed) controller.addError(error);
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
  }) =>
      throw UnimplementedError();

  @override
  Future<void> selectProfilePhoto({
    required String organizationId,
    required String photoId,
  }) =>
      throw UnimplementedError();

  @override
  Stream<String?> watchSelectedProfilePhotoRef({
    required String organizationId,
    required String customerId,
  }) =>
      Stream.value(null);
}

class _FakeCustomerPhotoPicker implements CustomerPhotoPicker {
  _FakeCustomerPhotoPicker({this.result});

  final PickedCustomerPhoto? result;
  int callCount = 0;
  CustomerPhotoPickSource? lastSource;

  @override
  Future<PickedCustomerPhoto?> pickImage({
    required CustomerPhotoPickSource source,
  }) async {
    callCount++;
    lastSource = source;
    return result;
  }
}
