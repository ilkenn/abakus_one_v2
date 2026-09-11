import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/qr/application/identity/guest_session_id_generator.dart';
import 'package:abakus_one_v2/features/qr/application/use_cases/open_table_guest_session_from_qr_scan.dart';
import 'package:abakus_one_v2/features/qr/data/table_guest_session_gateway.dart';
import 'package:abakus_one_v2/features/qr/data/technical_identity_provider.dart';

class _FakeTechnicalIdentityProvider implements TechnicalIdentityProvider {
  _FakeTechnicalIdentityProvider(this.uid);

  final String uid;
  int callCount = 0;

  @override
  Future<String> ensureSignedIn() async {
    callCount++;
    return uid;
  }

  @override
  String? get currentUid => uid;
}

class _FakeTableGuestSessionGateway implements TableGuestSessionGateway {
  _FakeTableGuestSessionGateway({this.openResult, this.openError});

  final OpenedTableGuestSession? openResult;
  final Object? openError;

  @override
  Future<TableQrPreview> resolveToken(String token) async {
    throw UnimplementedError(
      'Not used by OpenTableGuestSessionFromQrScan — the preview call is '
      'made separately by the screen before this use case ever runs.',
    );
  }

  @override
  Future<OpenedTableGuestSession> openSession(String token) async {
    if (openError != null) throw openError!;
    return openResult!;
  }

  @override
  Future<void> createServiceRequest({
    required String guestSessionId,
    required ServiceRequestType type,
  }) async {
    throw UnimplementedError('Not used by OpenTableGuestSessionFromQrScan.');
  }
}

void main() {
  final now = DateTime(2026, 8, 9, 12);
  final opened = OpenedTableGuestSession(
    sessionId: 'tgs-1',
    organizationId: 'org-1',
    restaurantId: 'restaurant-1',
    branchId: 'branch-1',
    tableId: 'table-1',
    tableDisplayName: 'Masa 12',
    branchDisplayName: 'Abaküs Ortaköy',
    expiresAt: now.add(const Duration(hours: 6)),
  );

  test(
      'establishes technical identity before opening the session, and '
      'populates ActiveTableContext from the callable response', () async {
    final identity = _FakeTechnicalIdentityProvider('anon-uid-1');
    final gateway = _FakeTableGuestSessionGateway(openResult: opened);
    final useCase = OpenTableGuestSessionFromQrScan(
      gateway: gateway,
      identityProvider: identity,
      guestSessionIdGenerator: SequentialGuestSessionIdGenerator(),
    );

    final context = await useCase.call('some-token');

    expect(identity.callCount, 1);
    expect(context.restaurantId, 'restaurant-1');
    expect(context.branchId, 'branch-1');
    expect(context.branchName, 'Abaküs Ortaköy');
    expect(context.tableId, 'table-1');
    expect(context.tableName, 'Masa 12');
    expect(context.session.id, 'tgs-1');
    expect(context.session.restaurantId, 'restaurant-1');
    expect(context.session.branchId, 'branch-1');
    expect(context.session.tableId, 'table-1');
    expect(context.guestSession.tableSessionId, 'tgs-1');
  });

  test(
      'restaurantId is threaded from the callable response, independent of '
      'branchId — proves the two fields propagate separately, not by '
      'coincidence', () async {
    final identity = _FakeTechnicalIdentityProvider('anon-uid-3');
    final gateway = _FakeTableGuestSessionGateway(
      openResult: OpenedTableGuestSession(
        sessionId: 'tgs-2',
        organizationId: 'org-2',
        restaurantId: 'restaurant-abakus-2',
        branchId: 'branch-ortakoy-2',
        tableId: 'table-2',
        tableDisplayName: 'Masa 4',
        branchDisplayName: 'Abaküs Beşiktaş',
        expiresAt: now.add(const Duration(hours: 6)),
      ),
    );
    final useCase = OpenTableGuestSessionFromQrScan(
      gateway: gateway,
      identityProvider: identity,
      guestSessionIdGenerator: SequentialGuestSessionIdGenerator(),
    );

    final context = await useCase.call('some-other-token');

    expect(context.restaurantId, 'restaurant-abakus-2');
    expect(context.branchId, 'branch-ortakoy-2');
    expect(context.session.restaurantId, 'restaurant-abakus-2');
  });

  test(
      'reuses an already-signed-in identity (a real customer or a prior '
      'anonymous uid) — never signs in a second time on top of it — and '
      'the resulting guest session is still never attributed to a '
      'customer account', () async {
    final identity = _FakeTechnicalIdentityProvider('existing-customer-uid');
    final gateway = _FakeTableGuestSessionGateway(openResult: opened);
    final useCase = OpenTableGuestSessionFromQrScan(
      gateway: gateway,
      identityProvider: identity,
      guestSessionIdGenerator: SequentialGuestSessionIdGenerator(),
    );

    final context = await useCase.call('some-token');

    // The orchestration always delegates the "reuse vs. create" decision
    // to TechnicalIdentityProvider itself and calls it exactly once —
    // this proves the use case never second-guesses or duplicates that
    // decision.
    expect(identity.callCount, 1);
    // Regardless of whose uid was actually used technically, the guest
    // session itself must never look like a normal authenticated
    // customer session.
    expect(context.guestSession.authenticatedUserId, isNull);
  });

  test(
      'reservationContextId is threaded from the gateway response into '
      'ActiveTableContext — Faz R.1C.2', () async {
    final identity = _FakeTechnicalIdentityProvider('anon-uid-rc');
    final gateway = _FakeTableGuestSessionGateway(
      openResult: OpenedTableGuestSession(
        sessionId: 'tgs-rc',
        organizationId: 'org-1',
        restaurantId: 'restaurant-1',
        branchId: 'branch-1',
        tableId: 'table-1',
        tableDisplayName: 'Masa 12',
        branchDisplayName: 'Abaküs Ortaköy',
        expiresAt: now.add(const Duration(hours: 6)),
        reservationContextId: 'RES_123',
      ),
    );
    final useCase = OpenTableGuestSessionFromQrScan(
      gateway: gateway,
      identityProvider: identity,
      guestSessionIdGenerator: SequentialGuestSessionIdGenerator(),
    );

    final context = await useCase.call('some-token');

    expect(context.reservationContextId, 'RES_123');
  });

  test(
      'reservationContextId is null for the ordinary walk-in case — the '
      'default when the gateway response omits it', () async {
    final identity = _FakeTechnicalIdentityProvider('anon-uid-walkin');
    final gateway = _FakeTableGuestSessionGateway(openResult: opened);
    final useCase = OpenTableGuestSessionFromQrScan(
      gateway: gateway,
      identityProvider: identity,
      guestSessionIdGenerator: SequentialGuestSessionIdGenerator(),
    );

    final context = await useCase.call('some-token');

    expect(context.reservationContextId, isNull);
  });

  test(
      'propagates a gateway failure (invalid/expired/notFound token) '
      'without producing a context', () async {
    final identity = _FakeTechnicalIdentityProvider('anon-uid-2');
    final gateway = _FakeTableGuestSessionGateway(
      openError: const TableGuestSessionException(
        'failed-precondition',
        'QR code is expired.',
      ),
    );
    final useCase = OpenTableGuestSessionFromQrScan(
      gateway: gateway,
      identityProvider: identity,
      guestSessionIdGenerator: SequentialGuestSessionIdGenerator(),
    );

    await expectLater(
      useCase.call('some-token'),
      throwsA(isA<TableGuestSessionException>()),
    );
  });
}
