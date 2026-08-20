import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/customer_photos/data/customer_photo_gateway.dart';
import 'package:abakus_one_v2/features/customer_photos/presentation/providers/customer_photo_providers.dart';
import 'package:abakus_one_v2/features/profile/presentation/screens/customer_photo_management_screen.dart';
import 'package:abakus_one_v2/features/profile/presentation/widgets/profile_customer_photos_card.dart';
import 'package:abakus_one_v2/shared/models/customer_photo.dart';
import 'package:abakus_one_v2/shared/models/customer_photo_status.dart';

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

  Future<void> pumpCard(WidgetTester tester,
      {required _FakeCustomerPhotoGateway gateway}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider
              .overrideWith(() => SeededAuthNotifier(authenticatedState())),
          customerPhotoGatewayProvider.overrideWithValue(gateway),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ProfileCustomerPhotosCard()),
        ),
      ),
    );
  }

  testWidgets('renders the entry-point title', (tester) async {
    final gateway = _FakeCustomerPhotoGateway();
    await pumpCard(tester, gateway: gateway);
    gateway.emitGallery([]);
    await tester.pumpAndSettle();

    expect(find.text('Profil Fotoğraflarım'), findsOneWidget);
  });

  testWidgets('shows the real active count, excluding rejected photos',
      (tester) async {
    final gateway = _FakeCustomerPhotoGateway();
    await pumpCard(tester, gateway: gateway);
    gateway.emitGallery([
      CustomerPhoto(
        id: 'p1',
        customerId: 'customer-uid-1',
        organizationId: 'org-1',
        photoRef: 'tenants/org-1/customerPhotos/customer-uid-1/p1',
        status: CustomerPhotoStatus.approved,
        uploadedAt: DateTime(2026, 8, 1),
        revision: 1,
      ),
      CustomerPhoto(
        id: 'p2',
        customerId: 'customer-uid-1',
        organizationId: 'org-1',
        photoRef: 'tenants/org-1/customerPhotos/customer-uid-1/p2',
        status: CustomerPhotoStatus.rejected,
        uploadedAt: DateTime(2026, 8, 1),
        revision: 1,
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('1 / 10 fotoğraf'), findsOneWidget);
  });

  testWidgets('tapping the card opens CustomerPhotoManagementScreen',
      (tester) async {
    final gateway = _FakeCustomerPhotoGateway();
    await pumpCard(tester, gateway: gateway);
    gateway.emitGallery([]);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('profileCustomerPhotosCard')));
    await tester.pumpAndSettle();

    expect(find.byType(CustomerPhotoManagementScreen), findsOneWidget);
  });

  testWidgets(
      'never crashes when the gallery stream errors from a genuinely fresh state (no cached value yet) — the exact scenario that previously crashed via the unsafe AsyncValue.value getter',
      (tester) async {
    // seedOnListen: false — reproduces a true first-ever AsyncError with
    // NO previous cached value, the specific state in which
    // `AsyncValue.value` (unlike `.valueOrNull`) rethrows the underlying
    // error. This is the exact real bug this widget's own fix addresses
    // (found via `otp_screen_test.dart` unexpectedly crashing before the
    // `.valueOrNull` fix).
    final gateway = _FakeCustomerPhotoGateway(seedOnListen: false);
    await pumpCard(tester, gateway: gateway);
    gateway.emitError(Exception('unavailable'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Fotoğraflarını yönet'), findsOneWidget);
  });
}

class _FakeCustomerPhotoGateway implements CustomerPhotoGateway {
  _FakeCustomerPhotoGateway({this.seedOnListen = true});

  final bool seedOnListen;
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
      onListen: seedOnListen ? () => controller.add(_photos) : null,
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
