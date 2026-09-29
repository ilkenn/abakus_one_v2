import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/qr/data/table_guest_session_firestore_client.dart';
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

/// Controllable fake for the Client Staleness Check's live-stream provider
/// — `findById` is unused by [TableContextBadge] (it only watches
/// [watchById]) so it throws if ever called, matching this file's own
/// "unused interface members throw" convention.
class _FakeTableGuestSessionFirestoreClient
    implements TableGuestSessionFirestoreClient {
  final _controller = StreamController<TableGuestSessionSnapshot?>.broadcast();

  void emit(TableGuestSessionSnapshot? snapshot) => _controller.add(snapshot);

  @override
  Future<TableGuestSessionSnapshot?> findById(String sessionId) async =>
      throw UnimplementedError();

  @override
  Stream<TableGuestSessionSnapshot?> watchById(String sessionId) =>
      _controller.stream;
}

ActiveTableContext _fakeContext({DateTime? expiresAt}) {
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
      expiresAt: expiresAt,
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
    final firestoreClient = _FakeTableGuestSessionFirestoreClient();
    final container = ProviderContainer(overrides: [
      tableGuestSessionFirestoreClientProvider
          .overrideWithValue(firestoreClient),
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

    expect(find.text('Abaküs Ortaköy · Masa 12'), findsOneWidget);
  });

  testWidgets(
      'garson cagir dokunusu dogru guestSessionId (session.id, guestSession.id DEGIL) ile istegi gonderir',
      (tester) async {
    final gateway = _FakeTableGuestSessionGateway();
    final firestoreClient = _FakeTableGuestSessionFirestoreClient();
    final container = ProviderContainer(overrides: [
      tableGuestSessionGatewayProvider.overrideWithValue(gateway),
      tableGuestSessionFirestoreClientProvider
          .overrideWithValue(firestoreClient),
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

  // 2026-09-29 — Client Staleness Check: an early, visual-only warning
  // (never blocks cart actions — the real enforcement stays at checkout)
  // when the guest's table session is expired or has been closed.
  group('bayatlik uyarisi', () {
    testWidgets('yerel expiresAt gecmisteyse uyari durumu gosterilir',
        (tester) async {
      final firestoreClient = _FakeTableGuestSessionFirestoreClient();
      final container = ProviderContainer(overrides: [
        tableGuestSessionFirestoreClientProvider
            .overrideWithValue(firestoreClient),
      ]);
      addTearDown(container.dispose);
      container.read(activeTableContextProvider.notifier).set(
            _fakeContext(expiresAt: DateTime(2020, 1, 1)),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: TableContextBadge()),
          ),
        ),
      );

      expect(
        find.text('Oturum süresi doldu — QR kodu tekrar okutun'),
        findsOneWidget,
      );
      expect(find.text('Abaküs Ortaköy · Masa 12'), findsNothing);
      expect(find.byIcon(Icons.room_service_outlined), findsNothing);
      expect(find.byIcon(Icons.receipt_long_outlined), findsNothing);
    });

    testWidgets(
        'yerel expiresAt gelecekteyken canli stream kapali durum yayinlarsa erken tespit edilir',
        (tester) async {
      final firestoreClient = _FakeTableGuestSessionFirestoreClient();
      final container = ProviderContainer(overrides: [
        tableGuestSessionFirestoreClientProvider
            .overrideWithValue(firestoreClient),
      ]);
      addTearDown(container.dispose);
      container.read(activeTableContextProvider.notifier).set(
            _fakeContext(
                expiresAt: DateTime.now().add(const Duration(hours: 6))),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: TableContextBadge()),
          ),
        ),
      );
      // Staff closed the table well before natural TTL expiry.
      firestoreClient.emit(TableGuestSessionSnapshot(
        status: 'closed',
        expiresAt: DateTime.now().add(const Duration(hours: 6)),
      ));
      await tester.pump();

      expect(
        find.text('Oturum süresi doldu — QR kodu tekrar okutun'),
        findsOneWidget,
      );
    });

    testWidgets(
        'stream henuz veri getirmediyse (loading) yanlis-pozitif bayatlik gostermez',
        (tester) async {
      final firestoreClient = _FakeTableGuestSessionFirestoreClient();
      final container = ProviderContainer(overrides: [
        tableGuestSessionFirestoreClientProvider
            .overrideWithValue(firestoreClient),
      ]);
      addTearDown(container.dispose);
      container.read(activeTableContextProvider.notifier).set(
            _fakeContext(
                expiresAt: DateTime.now().add(const Duration(hours: 6))),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: TableContextBadge()),
          ),
        ),
      );
      // Deliberately never emits on firestoreClient — stream stays loading.

      expect(find.text('Abaküs Ortaköy · Masa 12'), findsOneWidget);
      expect(
        find.text('Oturum süresi doldu — QR kodu tekrar okutun'),
        findsNothing,
      );
    });

    testWidgets(
        'her ikisi de aktifken normal rozet ve servis butonlari calisir durumda kalir',
        (tester) async {
      final firestoreClient = _FakeTableGuestSessionFirestoreClient();
      final container = ProviderContainer(overrides: [
        tableGuestSessionFirestoreClientProvider
            .overrideWithValue(firestoreClient),
      ]);
      addTearDown(container.dispose);
      container.read(activeTableContextProvider.notifier).set(
            _fakeContext(
                expiresAt: DateTime.now().add(const Duration(hours: 6))),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: TableContextBadge()),
          ),
        ),
      );
      firestoreClient.emit(TableGuestSessionSnapshot(
        status: 'active',
        expiresAt: DateTime.now().add(const Duration(hours: 6)),
      ));
      await tester.pump();

      expect(find.text('Abaküs Ortaköy · Masa 12'), findsOneWidget);
      expect(find.byIcon(Icons.room_service_outlined), findsOneWidget);
      expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
    });
  });
}
