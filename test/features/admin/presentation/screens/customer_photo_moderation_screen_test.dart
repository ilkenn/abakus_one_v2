import 'package:abakus_one_v2/bootstrap/firebase_ready_provider.dart';
import 'package:abakus_one_v2/features/admin/application/use_cases/moderate_customer_photo.dart';
import 'package:abakus_one_v2/features/admin/data/customer_photo_moderation_gateway.dart';
import 'package:abakus_one_v2/features/admin/data/customer_photo_repository.dart';
import 'package:abakus_one_v2/features/admin/presentation/providers/admin_dependencies_provider.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/customer_photo_moderation_screen.dart';
import 'package:abakus_one_v2/shared/models/customer_photo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/admin_test_fixtures.dart';

CustomerPhoto _buildPhoto({
  String id = 'photo-1',
  String customerId = 'customer-1',
  String organizationId = 'org-1',
}) {
  return CustomerPhoto(
    id: id,
    customerId: customerId,
    organizationId: organizationId,
    photoRef: 'tenants/$organizationId/customerPhotos/$customerId/$id',
    uploadedAt: DateTime(2026, 10, 27),
    revision: 1,
  );
}

/// Records every call it receives instead of actually reaching a real
/// Cloud Function — proves `_moderate` routes through the gateway (not
/// the in-memory use case) once Firebase is "ready".
class _RecordingModerationGateway implements CustomerPhotoModerationGateway {
  String? lastPhotoId;
  CustomerPhotoModerationAction? lastAction;
  int callCount = 0;

  @override
  Future<void> moderate({
    required String photoId,
    required CustomerPhotoModerationAction action,
    String? rejectionReason,
  }) async {
    callCount += 1;
    lastPhotoId = photoId;
    lastAction = action;
  }
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required CustomerPhotoRepository repository,
  bool firebaseReady = false,
  CustomerPhotoModerationGateway? gateway,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        customerPhotoRepositoryProvider.overrideWithValue(repository),
        firebaseReadyProvider.overrideWithValue(firebaseReady),
        if (gateway != null)
          customerPhotoModerationGatewayProvider.overrideWithValue(gateway),
      ],
      child: const MaterialApp(
        home: CustomerPhotoModerationScreen(
          authorizationPolicy: AllowAllAdminPolicy(),
          performedByStaffId: 'staff-1',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an empty queue shows the empty-state view', (tester) async {
    await _pumpScreen(tester, repository: InMemoryCustomerPhotoRepository());

    expect(find.text('İncelenecek fotoğraf yok.'), findsOneWidget);
  });

  testWidgets('shows a pending photo awaiting review', (tester) async {
    final repository = InMemoryCustomerPhotoRepository();
    await repository.save(_buildPhoto());

    await _pumpScreen(tester, repository: repository);

    expect(find.textContaining('customer-1'), findsOneWidget);
  });

  testWidgets(
      'pre-Firebase (dev/test): approving a photo goes through the in-memory '
      'ModerateCustomerPhoto use case, never the gateway', (tester) async {
    final repository = InMemoryCustomerPhotoRepository();
    await repository.save(_buildPhoto());
    final gateway = _RecordingModerationGateway();

    await _pumpScreen(
      tester,
      repository: repository,
      firebaseReady: false,
      gateway: gateway,
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Onayla'));
    await tester.pumpAndSettle();

    expect(gateway.callCount, 0);
    final updated = await repository.findById('photo-1');
    expect(updated!.status.name, 'approved');
  });

  testWidgets(
      'once Firebase is ready: approving a photo calls the real moderation '
      'gateway, never writes to the repository directly', (tester) async {
    final repository = InMemoryCustomerPhotoRepository();
    await repository.save(_buildPhoto());
    final gateway = _RecordingModerationGateway();

    await _pumpScreen(
      tester,
      repository: repository,
      firebaseReady: true,
      gateway: gateway,
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Onayla'));
    await tester.pumpAndSettle();

    expect(gateway.callCount, 1);
    expect(gateway.lastPhotoId, 'photo-1');
    expect(gateway.lastAction, CustomerPhotoModerationAction.approve);
  });
}
