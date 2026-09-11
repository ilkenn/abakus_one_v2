import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/qr/data/table_guest_session_gateway.dart';
import 'package:abakus_one_v2/features/qr/domain/models/active_table_context.dart';
import 'package:abakus_one_v2/features/qr/domain/models/guest_session.dart';
import 'package:abakus_one_v2/features/qr/domain/models/table_session.dart';
import 'package:abakus_one_v2/features/qr/presentation/providers/active_table_context_provider.dart';
import 'package:abakus_one_v2/features/qr/presentation/providers/table_guest_session_dependencies_provider.dart';
import 'package:abakus_one_v2/features/qr/presentation/widgets/table_context_badge.dart';

class _FakeTableGuestSessionGateway implements TableGuestSessionGateway {
  String? lastGuestSessionId;
  ServiceRequestType? lastType;
  int callCount = 0;

  @override
  Future<TableQrPreview> resolveToken(String token) async =>
      throw UnimplementedError();

  @override
  Future<OpenedTableGuestSession> openSession(String token) async =>
      throw UnimplementedError();

  @override
  Future<void> createServiceRequest({
    required String guestSessionId,
    required ServiceRequestType type,
  }) async {
    callCount++;
    lastGuestSessionId = guestSessionId;
    lastType = type;
  }
}

ActiveTableContext _fakeContext() {
  final now = DateTime(2026, 8, 9);
  return ActiveTableContext(
    restaurantId: 'restaurant-1',
    branchId: 'branch-1',
    branchName: 'Abaküs Ortaköy',
    tableId: 'dev-table-12',
    tableName: 'Masa 12',
    session: TableSession(
      id: 'tsession-1',
      restaurantId: 'restaurant-1',
      branchId: 'branch-1',
      tableId: 'dev-table-12',
      status: TableSessionStatus.active,
      openedAt: now,
      guestSessionIds: const [],
      activeOrderIds: const [],
    ),
    guestSession: GuestSession(
      id: 'gsession-1',
      tableSessionId: 'tsession-1',
      branchId: 'branch-1',
      tableId: 'dev-table-12',
      detectedLanguageCode: 'tr',
      selectedLanguageCode: 'tr',
      createdAt: now,
      lastSeenAt: now,
      status: GuestSessionStatus.active,
    ),
  );
}

void main() {
  testWidgets('aktif masa baglami yokken hicbir sey gostermez', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: TableContextBadge()),
        ),
      ),
    );

    expect(find.byType(TableContextBadge), findsOneWidget);
    expect(find.textContaining('Masa'), findsNothing);
  });

  testWidgets('aktif masa baglami varken sube ve masa adini gosterir', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(activeTableContextProvider.notifier).set(_fakeContext());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: TableContextBadge()),
        ),
      ),
    );

    expect(find.text('Abaküs Ortaköy · Masa 12'), findsOneWidget);
  });

  testWidgets(
      'garson cagir dokunusu dogru guestSessionId (session.id, guestSession.id DEGIL) ile istegi gonderir',
      (tester) async {
    final gateway = _FakeTableGuestSessionGateway();
    final container = ProviderContainer(overrides: [
      tableGuestSessionGatewayProvider.overrideWithValue(gateway),
    ]);
    addTearDown(container.dispose);
    container.read(activeTableContextProvider.notifier).set(_fakeContext());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: TableContextBadge()),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.room_service_outlined));
    await tester.pumpAndSettle();

    expect(gateway.callCount, 1);
    expect(gateway.lastGuestSessionId, 'tsession-1');
    expect(gateway.lastType, ServiceRequestType.callWaiter);
    expect(find.text('İsteğiniz iletildi.'), findsOneWidget);
  });
}
