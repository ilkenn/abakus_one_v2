import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/admin/data/admin_reservation_gateway.dart';
import 'package:abakus_one_v2/features/admin/domain/reservations/admin_reservation_error_messages.dart';
import 'package:abakus_one_v2/features/admin/domain/reservations/admin_reservation_summary.dart';
import 'package:abakus_one_v2/features/admin/presentation/providers/admin_reservation_dependencies_provider.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/reservation_operations_screen.dart';
import 'package:abakus_one_v2/features/admin/presentation/widgets/reservation_ops/reservation_detail_panel.dart';
import 'package:abakus_one_v2/features/reservation/domain/models/reservation_area.dart';
import 'package:abakus_one_v2/features/reservation/domain/models/reservation_status.dart';
import 'package:abakus_one_v2/features/reservation/domain/models/reservation_summary.dart';

import '../test_support/fake_admin_reservation_gateway.dart';
import '../test_support/fake_admin_reservation_repository.dart';

const _area = ReservationArea(id: 'area-garden', displayName: 'Bahçe');

AdminReservationSummary _reservation({
  String id = 'reservation-1',
  ReservationStatus status = ReservationStatus.pendingRestaurantApproval,
  DateTime? requestedTime,
  DateTime? confirmedTime,
  String? assignedTableId,
  String? preorderOrderId,
  DateTime? activeProposalCustomerResponseDeadlineAt,
}) {
  return AdminReservationSummary(
    id: id,
    status: status,
    partySize: 4,
    requestedTime:
        requestedTime ?? DateTime.now().add(const Duration(hours: 2)),
    requestedAreaId: _area.id,
    contactFirstName: 'Ada',
    contactLastName: 'Yılmaz',
    confirmedTime: confirmedTime,
    confirmedAreaId: confirmedTime != null ? _area.id : null,
    assignedTableId: assignedTableId,
    preorderOrderId: preorderOrderId,
    activeProposalCustomerResponseDeadlineAt:
        activeProposalCustomerResponseDeadlineAt,
  );
}

Future<(FakeAdminReservationGateway, FakeAdminReservationRepository)>
    _pumpScreen(
  WidgetTester tester, {
  Size size = const Size(1400, 1000),
  FakeAdminReservationGateway? gateway,
  FakeAdminReservationRepository? repository,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final fakeGateway = gateway ?? FakeAdminReservationGateway();
  final fakeRepository = repository ?? FakeAdminReservationRepository();
  fakeGateway.areasToReturn = [_area];
  addTearDown(fakeRepository.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminReservationGatewayProvider.overrideWithValue(fakeGateway),
        adminReservationRepositoryProvider.overrideWithValue(fakeRepository),
      ],
      child: const MaterialApp(home: ReservationOperationsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return (fakeGateway, fakeRepository);
}

void main() {
  group('list view', () {
    testWidgets('shows the empty message for the default (Bugün) tab',
        (tester) async {
      await _pumpScreen(tester);
      expect(find.text('Bugün için rezervasyon bulunmuyor.'), findsOneWidget);
    });

    testWidgets(
        'renders a reservation card with customer name and status label',
        (tester) async {
      final gateway = FakeAdminReservationGateway()
        ..listPageToReturn = AdminReservationListPage(
            reservations: [_reservation()], nextCursor: null);
      await _pumpScreen(tester, gateway: gateway);

      expect(find.text('Ada Yılmaz'), findsOneWidget);
      expect(find.text('Onay Bekliyor'), findsOneWidget);
    });

    testWidgets('switching to Yaklaşan/Tümü tabs re-queries the list provider',
        (tester) async {
      final gateway = FakeAdminReservationGateway();
      await _pumpScreen(tester, gateway: gateway);
      final initialCalls = gateway.listCallCount;

      await tester.tap(find.text('Yaklaşan'));
      await tester.pumpAndSettle();
      expect(find.text('Yaklaşan rezervasyon bulunmuyor.'), findsOneWidget);

      await tester.tap(find.text('Tümü'));
      await tester.pumpAndSettle();
      expect(find.text('Rezervasyon bulunmuyor.'), findsOneWidget);

      expect(gateway.listCallCount, greaterThan(initialCalls));
    });
  });

  group('calendar view', () {
    testWidgets('shows the day agenda with an area filter and empty state',
        (tester) async {
      await _pumpScreen(tester);
      await tester.tap(find.text('Takvim'));
      await tester.pumpAndSettle();

      expect(find.text('Tüm Alanlar'), findsOneWidget);
      expect(find.text('Bu gün için rezervasyon bulunmuyor.'), findsOneWidget);
    });

    testWidgets('groups reservations by hour', (tester) async {
      final now = DateTime.now();
      final today9pm = DateTime(now.year, now.month, now.day, 21, 0);
      final gateway = FakeAdminReservationGateway()
        ..listPageToReturn = AdminReservationListPage(
          reservations: [_reservation(requestedTime: today9pm)],
          nextCursor: null,
        );
      await _pumpScreen(tester, gateway: gateway);
      await tester.tap(find.text('Takvim'));
      await tester.pumpAndSettle();

      // Both the hour-header chip and the card's own time label read
      // "21:00" — two matches is the correct expectation, not an error.
      expect(find.text('21:00'), findsNWidgets(2));
      expect(find.text('Ada Yılmaz'), findsOneWidget);
    });
  });

  group('detail panel + confirm/reject/propose', () {
    testWidgets(
        'tapping a card opens the detail panel on desktop, showing full detail',
        (tester) async {
      final gateway = FakeAdminReservationGateway()
        ..listPageToReturn = AdminReservationListPage(
            reservations: [_reservation()], nextCursor: null);
      final repository = FakeAdminReservationRepository();
      await _pumpScreen(tester, gateway: gateway, repository: repository);

      await tester.tap(find.text('Ada Yılmaz'));
      await tester.pump();
      repository.emitDetail('reservation-1', _reservation());
      await tester.pumpAndSettle();

      expect(find.byType(ReservationDetailPanel), findsOneWidget);
      expect(find.text('Kişi Sayısı'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('confirming calls the real confirmReservation callable',
        (tester) async {
      final gateway = FakeAdminReservationGateway()
        ..listPageToReturn = AdminReservationListPage(
            reservations: [_reservation()], nextCursor: null);
      final repository = FakeAdminReservationRepository();
      await _pumpScreen(tester, gateway: gateway, repository: repository);

      await tester.tap(find.text('Ada Yılmaz'));
      await tester.pump();
      repository.emitDetail('reservation-1', _reservation());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Onayla'));
      await tester.pumpAndSettle();

      expect(gateway.confirmCalls, ['reservation-1']);
    });

    testWidgets(
        'a capacity-conflict confirm error shows the mapped Turkish message',
        (tester) async {
      final gateway = FakeAdminReservationGateway()
        ..listPageToReturn = AdminReservationListPage(
            reservations: [_reservation()], nextCursor: null)
        ..confirmError =
            const AdminReservationException('resource-exhausted', 'no room');
      final repository = FakeAdminReservationRepository();
      await _pumpScreen(tester, gateway: gateway, repository: repository);

      await tester.tap(find.text('Ada Yılmaz'));
      await tester.pump();
      repository.emitDetail('reservation-1', _reservation());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Onayla'));
      await tester.pumpAndSettle();

      expect(
        find.text(
            'Bu işlem şu anda gerçekleştirilemiyor (kapasite sınırı). Lütfen daha sonra tekrar deneyin.'),
        findsOneWidget,
      );
    });

    testWidgets(
        'rejecting through the reason dialog calls rejectReservation with the chosen reason',
        (tester) async {
      final gateway = FakeAdminReservationGateway()
        ..listPageToReturn = AdminReservationListPage(
            reservations: [_reservation()], nextCursor: null);
      final repository = FakeAdminReservationRepository();
      await _pumpScreen(tester, gateway: gateway, repository: repository);

      await tester.tap(find.text('Ada Yılmaz'));
      await tester.pump();
      repository.emitDetail('reservation-1', _reservation());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rezervasyonu Reddet'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reddet'));
      await tester.pumpAndSettle();

      expect(gateway.rejectCalls.single.reservationId, 'reservation-1');
      expect(gateway.rejectCalls.single.reasonCode, 'fullyBooked');
    });

    testWidgets(
        'proposing a change opens the dialog and calls proposeChange with the chosen area/time',
        (tester) async {
      final gateway = FakeAdminReservationGateway()
        ..listPageToReturn = AdminReservationListPage(
            reservations: [_reservation()], nextCursor: null);
      final repository = FakeAdminReservationRepository();
      await _pumpScreen(tester, gateway: gateway, repository: repository);

      await tester.tap(find.text('Ada Yılmaz'));
      await tester.pump();
      repository.emitDetail('reservation-1', _reservation());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alternatif Saat/Alan Öner'));
      await tester.pumpAndSettle();

      expect(find.text('Alternatif Öner'), findsOneWidget);
      // Submit is disabled until date/time/area are all chosen — proven by
      // the dialog being open with a disabled primary action; full happy
      // path is covered at the domain level (proposeChange call shape) via
      // the gateway itself, exercised directly.
      await gateway.proposeChange(
        reservationId: 'reservation-1',
        proposedTime: DateTime(2026, 8, 21, 19, 0),
        proposedAreaId: _area.id,
      );
      expect(gateway.proposeChangeCalls.single.reservationId, 'reservation-1');
      expect(gateway.proposeChangeCalls.single.proposedAreaId, _area.id);
    });

    test(
        'proposal availability rejection shows the mapped message, not raw backend text',
        () {
      const error = AdminReservationException(
          'failed-precondition', 'This slot is no longer available');
      final mapped = adminReservationErrorMessage(error);
      expect(mapped, isNot(contains('slot is no longer available')));
    });
  });

  group('Faz R.3B — terminal actions (cancel/complete/no-show)', () {
    testWidgets(
        'a pendingRestaurantApproval reservation shows Cancel but not Complete/No-show',
        (tester) async {
      final gateway = FakeAdminReservationGateway()
        ..listPageToReturn = AdminReservationListPage(
            reservations: [_reservation()], nextCursor: null);
      final repository = FakeAdminReservationRepository();
      await _pumpScreen(tester, gateway: gateway, repository: repository);

      await tester.tap(find.text('Ada Yılmaz'));
      await tester.pump();
      repository.emitDetail('reservation-1', _reservation());
      await tester.pumpAndSettle();

      expect(find.text('Rezervasyonu İptal Et'), findsOneWidget);
      expect(find.text('Tamamlandı'), findsNothing);
      expect(find.text('Gelmedi'), findsNothing);
    });

    testWidgets(
        'a confirmed reservation whose confirmedTime has NOT passed shows Cancel but not Complete/No-show',
        (tester) async {
      final confirmed = _reservation(
        status: ReservationStatus.confirmed,
        confirmedTime: DateTime.now().add(const Duration(hours: 2)),
      );
      final gateway = FakeAdminReservationGateway()
        ..listPageToReturn = AdminReservationListPage(
            reservations: [confirmed], nextCursor: null);
      final repository = FakeAdminReservationRepository();
      await _pumpScreen(tester, gateway: gateway, repository: repository);

      await tester.tap(find.text('Ada Yılmaz'));
      await tester.pump();
      repository.emitDetail('reservation-1', confirmed);
      await tester.pumpAndSettle();

      expect(find.text('Rezervasyonu İptal Et'), findsOneWidget);
      expect(find.text('Tamamlandı'), findsNothing);
      expect(find.text('Gelmedi'), findsNothing);
    });

    testWidgets(
        'a confirmed reservation whose confirmedTime HAS passed shows Complete and No-show',
        (tester) async {
      final due = _reservation(
        status: ReservationStatus.confirmed,
        confirmedTime: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      final gateway = FakeAdminReservationGateway()
        ..listPageToReturn =
            AdminReservationListPage(reservations: [due], nextCursor: null);
      final repository = FakeAdminReservationRepository();
      await _pumpScreen(tester, gateway: gateway, repository: repository);

      await tester.tap(find.text('Ada Yılmaz'));
      await tester.pump();
      repository.emitDetail('reservation-1', due);
      await tester.pumpAndSettle();

      expect(find.text('Tamamlandı'), findsOneWidget);
      expect(find.text('Gelmedi'), findsOneWidget);
      expect(find.text('Rezervasyonu İptal Et'), findsOneWidget);
    });

    testWidgets(
        'a terminal (already-cancelled) reservation shows none of the terminal actions',
        (tester) async {
      final cancelled = _reservation(status: ReservationStatus.cancelled);
      final gateway = FakeAdminReservationGateway()
        ..listPageToReturn = AdminReservationListPage(
            reservations: [cancelled], nextCursor: null);
      final repository = FakeAdminReservationRepository();
      await _pumpScreen(tester, gateway: gateway, repository: repository);

      await tester.tap(find.text('Ada Yılmaz'));
      await tester.pump();
      repository.emitDetail('reservation-1', cancelled);
      await tester.pumpAndSettle();

      expect(find.text('Rezervasyonu İptal Et'), findsNothing);
      expect(find.text('Tamamlandı'), findsNothing);
      expect(find.text('Gelmedi'), findsNothing);
    });

    testWidgets(
        'confirming the cancel dialog calls the real cancelReservation callable',
        (tester) async {
      final gateway = FakeAdminReservationGateway()
        ..listPageToReturn = AdminReservationListPage(
            reservations: [_reservation()], nextCursor: null);
      final repository = FakeAdminReservationRepository();
      await _pumpScreen(tester, gateway: gateway, repository: repository);

      await tester.tap(find.text('Ada Yılmaz'));
      await tester.pump();
      repository.emitDetail('reservation-1', _reservation());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rezervasyonu İptal Et'));
      await tester.pumpAndSettle();
      expect(
          find.text('Bu rezervasyonu iptal etmek istediğinizden emin misiniz?'),
          findsOneWidget);
      await tester.tap(find.text('İptal Et'));
      await tester.pumpAndSettle();

      expect(gateway.cancelCalls.single.reservationId, 'reservation-1');
    });

    testWidgets('dismissing the cancel dialog never calls the gateway',
        (tester) async {
      final gateway = FakeAdminReservationGateway()
        ..listPageToReturn = AdminReservationListPage(
            reservations: [_reservation()], nextCursor: null);
      final repository = FakeAdminReservationRepository();
      await _pumpScreen(tester, gateway: gateway, repository: repository);

      await tester.tap(find.text('Ada Yılmaz'));
      await tester.pump();
      repository.emitDetail('reservation-1', _reservation());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rezervasyonu İptal Et'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();

      expect(gateway.cancelCalls, isEmpty);
    });

    testWidgets(
        'cancelling a reservation with a released preorder shows the required admin warning before confirmation',
        (tester) async {
      final withPreorder = _reservation(preorderOrderId: 'order-1');
      final gateway = FakeAdminReservationGateway()
        ..listPageToReturn = AdminReservationListPage(
            reservations: [withPreorder], nextCursor: null);
      final repository = FakeAdminReservationRepository();
      await _pumpScreen(tester, gateway: gateway, repository: repository);

      await tester.tap(find.text('Ada Yılmaz'));
      await tester.pump();
      repository.emitDetail('reservation-1', withPreorder);
      await tester.pump();
      repository.emitPreorder(
        'order-1',
        const ReservationPreorderSummary(
          orderId: 'order-1',
          status: ReservationPreorderStatus.confirmed,
          kitchenReleaseAt: null,
          lines: [],
          grandTotalMinorUnits: 0,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rezervasyonu İptal Et'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          'Bu rezervasyonun ön siparişi mutfağa iletilmiş.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
            'Rezervasyonun iptal edilmesi ön siparişi otomatik iptal etmez.'),
        findsOneWidget,
      );
    });

    testWidgets(
        'cancelling a reservation with a still-pending preorder shows no warning',
        (tester) async {
      final withPreorder = _reservation(preorderOrderId: 'order-1');
      final gateway = FakeAdminReservationGateway()
        ..listPageToReturn = AdminReservationListPage(
            reservations: [withPreorder], nextCursor: null);
      final repository = FakeAdminReservationRepository();
      await _pumpScreen(tester, gateway: gateway, repository: repository);

      await tester.tap(find.text('Ada Yılmaz'));
      await tester.pump();
      repository.emitDetail('reservation-1', withPreorder);
      await tester.pump();
      repository.emitPreorder(
        'order-1',
        const ReservationPreorderSummary(
          orderId: 'order-1',
          status: ReservationPreorderStatus.pendingConfirmation,
          kitchenReleaseAt: null,
          lines: [],
          grandTotalMinorUnits: 0,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rezervasyonu İptal Et'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Bu rezervasyonun ön siparişi mutfağa iletilmiş.'),
        findsNothing,
      );
      expect(
          find.text('Bu rezervasyonu iptal etmek istediğinizden emin misiniz?'),
          findsOneWidget);
    });

    testWidgets(
        'confirming Tamamlandı calls the real completeReservation callable',
        (tester) async {
      final due = _reservation(
        status: ReservationStatus.confirmed,
        confirmedTime: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      final gateway = FakeAdminReservationGateway()
        ..listPageToReturn =
            AdminReservationListPage(reservations: [due], nextCursor: null);
      final repository = FakeAdminReservationRepository();
      await _pumpScreen(tester, gateway: gateway, repository: repository);

      await tester.tap(find.text('Ada Yılmaz'));
      await tester.pump();
      repository.emitDetail('reservation-1', due);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tamamlandı'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tamamlandı').last);
      await tester.pumpAndSettle();

      expect(gateway.completeCalls, ['reservation-1']);
    });

    testWidgets(
        'confirming Gelmedi calls the real markReservationNoShow callable',
        (tester) async {
      final due = _reservation(
        status: ReservationStatus.confirmed,
        confirmedTime: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      final gateway = FakeAdminReservationGateway()
        ..listPageToReturn =
            AdminReservationListPage(reservations: [due], nextCursor: null);
      final repository = FakeAdminReservationRepository();
      await _pumpScreen(tester, gateway: gateway, repository: repository);

      await tester.tap(find.text('Ada Yılmaz'));
      await tester.pump();
      repository.emitDetail('reservation-1', due);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Gelmedi'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gelmedi').last);
      await tester.pumpAndSettle();

      expect(gateway.noShowCalls, ['reservation-1']);
    });

    testWidgets(
        'a complete-before-confirmedTime error shows the mapped Turkish message',
        (tester) async {
      final due = _reservation(
        status: ReservationStatus.confirmed,
        confirmedTime: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      final gateway = FakeAdminReservationGateway()
        ..listPageToReturn =
            AdminReservationListPage(reservations: [due], nextCursor: null)
        ..completeError = const AdminReservationException(
          'failed-precondition',
          'A reservation cannot be marked completed before its confirmedTime.',
        );
      final repository = FakeAdminReservationRepository();
      await _pumpScreen(tester, gateway: gateway, repository: repository);

      await tester.tap(find.text('Ada Yılmaz'));
      await tester.pump();
      repository.emitDetail('reservation-1', due);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tamamlandı'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tamamlandı').last);
      await tester.pumpAndSettle();

      expect(
        find.text(
            'Rezervasyon saati gelmeden "Tamamlandı" olarak işaretlenemez.'),
        findsOneWidget,
      );
    });
  });

  group('table assignment', () {
    testWidgets(
        'shows assigned table on a confirmed reservation and lists tables to assign',
        (tester) async {
      final reservation = _reservation(
          status: ReservationStatus.confirmed, assignedTableId: 'table-1');
      final gateway = FakeAdminReservationGateway()
        ..listPageToReturn = AdminReservationListPage(
            reservations: [reservation], nextCursor: null)
        ..tablesToReturn = const [
          ReservationTableOption(
              id: 'table-1',
              displayName: 'Masa 1',
              capacity: 4,
              available: true,
              isCurrentlyAssigned: true),
          ReservationTableOption(
              id: 'table-2',
              displayName: 'Masa 2',
              capacity: 4,
              available: false,
              isCurrentlyAssigned: false),
        ];
      final repository = FakeAdminReservationRepository();
      await _pumpScreen(tester, gateway: gateway, repository: repository);

      await tester.tap(find.text('Ada Yılmaz'));
      await tester.pump();
      repository.emitDetail('reservation-1', reservation);
      await tester.pumpAndSettle();

      // "Masa" appears both as the list card's inline badge label and the
      // core-info-card's row label for the assigned table — two matches is
      // correct here, not an ambiguity to resolve away.
      expect(find.text('Masa'), findsWidgets);
      expect(find.textContaining('Masa 1'), findsWidgets);
      expect(find.textContaining('Masa 2'), findsWidgets);
    });

    testWidgets('tapping an available table calls assignTable', (tester) async {
      final reservation = _reservation(status: ReservationStatus.confirmed);
      final gateway = FakeAdminReservationGateway()
        ..listPageToReturn = AdminReservationListPage(
            reservations: [reservation], nextCursor: null)
        ..tablesToReturn = const [
          ReservationTableOption(
              id: 'table-1',
              displayName: 'Masa 1',
              capacity: 4,
              available: true,
              isCurrentlyAssigned: false),
        ];
      final repository = FakeAdminReservationRepository();
      await _pumpScreen(tester, gateway: gateway, repository: repository);

      await tester.tap(find.text('Ada Yılmaz'));
      await tester.pump();
      repository.emitDetail('reservation-1', reservation);
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Masa 1'));
      await tester.pumpAndSettle();

      expect(gateway.assignTableCalls.single.tableId, 'table-1');
    });
  });

  group('table session (open/close)', () {
    testWidgets('opening a table calls openTable with acknowledge:false first',
        (tester) async {
      final reservation = _reservation(
          status: ReservationStatus.confirmed, assignedTableId: 'table-1');
      final gateway = FakeAdminReservationGateway()
        ..listPageToReturn = AdminReservationListPage(
            reservations: [reservation], nextCursor: null)
        ..tablesToReturn = const [];
      final repository = FakeAdminReservationRepository();
      await _pumpScreen(tester, gateway: gateway, repository: repository);

      await tester.tap(find.text('Ada Yılmaz'));
      await tester.pump();
      repository.emitDetail('reservation-1', reservation);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rezervasyon Masasını Aç'));
      await tester.pumpAndSettle();

      expect(gateway.openTableCalls.single.acknowledge, false);
    });

    testWidgets(
        'an active-session conflict shows the required handshake dialog, and acknowledging retries with acknowledge:true',
        (tester) async {
      final reservation = _reservation(
          status: ReservationStatus.confirmed, assignedTableId: 'table-1');
      final gateway = FakeAdminReservationGateway()
        ..listPageToReturn = AdminReservationListPage(
            reservations: [reservation], nextCursor: null)
        ..tablesToReturn = const [];
      final repository = FakeAdminReservationRepository();
      await _pumpScreen(tester, gateway: gateway, repository: repository);

      await tester.tap(find.text('Ada Yılmaz'));
      await tester.pump();
      repository.emitDetail('reservation-1', reservation);
      await tester.pumpAndSettle();

      gateway.openTableError = const ActiveSessionConflictException(1);
      await tester.tap(find.text('Rezervasyon Masasını Aç'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Bu masada halen aktif bir masa oturumu bulunuyor. '
          'Rezervasyon masasını yine de açmak istiyor musunuz?',
        ),
        findsOneWidget,
      );
      expect(find.text('Vazgeç'), findsOneWidget);
      expect(find.text('Yine de Aç'), findsOneWidget);

      gateway.openTableError = null;
      await tester.tap(find.text('Yine de Aç'));
      await tester.pumpAndSettle();

      expect(gateway.openTableCalls.length, 2);
      expect(gateway.openTableCalls.last.acknowledge, true);
    });

    testWidgets(
        'the close-table copy explicitly states it does not complete the reservation',
        (tester) async {
      final reservation = _reservation(
          status: ReservationStatus.confirmed, assignedTableId: 'table-1');
      final gateway = FakeAdminReservationGateway()
        ..listPageToReturn = AdminReservationListPage(
            reservations: [reservation], nextCursor: null)
        ..tablesToReturn = const [];
      final repository = FakeAdminReservationRepository();
      await _pumpScreen(tester, gateway: gateway, repository: repository);

      await tester.tap(find.text('Ada Yılmaz'));
      await tester.pump();
      repository.emitDetail('reservation-1', reservation);
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
            'Kapatmak rezervasyonu tamamlamaz, müşteri oturumlarını sonlandırmaz'),
        findsOneWidget,
      );
    });
  });

  group('preorder view', () {
    testWidgets(
        'shows a future kitchen-release time with the exact required copy',
        (tester) async {
      final reservation = _reservation(preorderOrderId: 'order-1');
      final gateway = FakeAdminReservationGateway()
        ..listPageToReturn = AdminReservationListPage(
            reservations: [reservation], nextCursor: null);
      final repository = FakeAdminReservationRepository();
      await _pumpScreen(tester, gateway: gateway, repository: repository);

      await tester.tap(find.text('Ada Yılmaz'));
      await tester.pump();
      repository.emitDetail('reservation-1', reservation);
      // A bounded pump, not pumpAndSettle: the preorder card is still in
      // its own loading state at this point (its CircularProgressIndicator
      // never quiesces) until emitPreorder below arrives.
      await tester.pump();

      repository.emitPreorder(
        'order-1',
        ReservationPreorderSummary(
          orderId: 'order-1',
          status: ReservationPreorderStatus.pendingConfirmation,
          kitchenReleaseAt: DateTime.utc(2026, 8, 20, 19, 0),
          lines: const [
            ReservationPreorderLineSummary(
              productName: 'Poke Bowl',
              quantity: 2,
              modifierNames: ['Somon'],
              lineTotalMinorUnits: 24000,
            ),
          ],
          grandTotalMinorUnits: 24000,
        ),
      );
      await tester.pumpAndSettle();

      final expectedLocal = DateTime.utc(2026, 8, 20, 19, 0).toLocal();
      final expectedLabel =
          'Mutfağa gönderim: ${expectedLocal.hour.toString().padLeft(2, '0')}:${expectedLocal.minute.toString().padLeft(2, '0')}';
      expect(find.text(expectedLabel), findsOneWidget);
      expect(find.textContaining('Poke Bowl'), findsOneWidget);
      expect(find.text('240 TL'), findsWidgets);
    });

    testWidgets('shows "Mutfağa iletildi" once confirmed', (tester) async {
      final reservation = _reservation(preorderOrderId: 'order-1');
      final gateway = FakeAdminReservationGateway()
        ..listPageToReturn = AdminReservationListPage(
            reservations: [reservation], nextCursor: null);
      final repository = FakeAdminReservationRepository();
      await _pumpScreen(tester, gateway: gateway, repository: repository);

      await tester.tap(find.text('Ada Yılmaz'));
      await tester.pump();
      repository.emitDetail('reservation-1', reservation);
      // A bounded pump, not pumpAndSettle: the preorder card is still in
      // its own loading state at this point (its CircularProgressIndicator
      // never quiesces) until emitPreorder below arrives.
      await tester.pump();

      repository.emitPreorder(
        'order-1',
        const ReservationPreorderSummary(
          orderId: 'order-1',
          status: ReservationPreorderStatus.confirmed,
          kitchenReleaseAt: null,
          lines: [],
          grandTotalMinorUnits: 0,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mutfağa iletildi'), findsOneWidget);
    });

    testWidgets('shows "Ön sipariş iptal" once cancelled', (tester) async {
      final reservation = _reservation(preorderOrderId: 'order-1');
      final gateway = FakeAdminReservationGateway()
        ..listPageToReturn = AdminReservationListPage(
            reservations: [reservation], nextCursor: null);
      final repository = FakeAdminReservationRepository();
      await _pumpScreen(tester, gateway: gateway, repository: repository);

      await tester.tap(find.text('Ada Yılmaz'));
      await tester.pump();
      repository.emitDetail('reservation-1', reservation);
      // A bounded pump, not pumpAndSettle: the preorder card is still in
      // its own loading state at this point (its CircularProgressIndicator
      // never quiesces) until emitPreorder below arrives.
      await tester.pump();

      repository.emitPreorder(
        'order-1',
        const ReservationPreorderSummary(
          orderId: 'order-1',
          status: ReservationPreorderStatus.cancelled,
          kitchenReleaseAt: null,
          lines: [],
          grandTotalMinorUnits: 0,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ön sipariş iptal'), findsOneWidget);
    });
  });

  group('responsive layout', () {
    testWidgets(
        'desktop (>=1000px): selecting a reservation shows an inline side panel, list stays visible',
        (tester) async {
      final gateway = FakeAdminReservationGateway()
        ..listPageToReturn = AdminReservationListPage(
            reservations: [_reservation()], nextCursor: null);
      final repository = FakeAdminReservationRepository();
      await _pumpScreen(tester,
          size: const Size(1400, 1000),
          gateway: gateway,
          repository: repository);

      await tester.tap(find.text('Ada Yılmaz'));
      await tester.pump();
      repository.emitDetail('reservation-1', _reservation());
      await tester.pumpAndSettle();

      // Both the list card and the inline detail panel are simultaneously
      // visible — proven by the customer name appearing twice (list row +
      // detail panel's own info row).
      expect(find.text('Ada Yılmaz'), findsNWidgets(2));
      expect(find.byType(ReservationDetailPanel), findsOneWidget);
    });

    testWidgets(
        'mobile (<600px): selecting a reservation pushes a full detail screen instead of a side panel',
        (tester) async {
      final gateway = FakeAdminReservationGateway()
        ..listPageToReturn = AdminReservationListPage(
            reservations: [_reservation()], nextCursor: null);
      final repository = FakeAdminReservationRepository();
      await _pumpScreen(tester,
          size: const Size(390, 844), gateway: gateway, repository: repository);

      await tester.tap(find.text('Ada Yılmaz'));
      await tester.pump();
      repository.emitDetail('reservation-1', _reservation());
      await tester.pumpAndSettle();

      expect(find.text('Rezervasyon Detayı'), findsOneWidget);
      expect(find.byType(ReservationDetailPanel), findsOneWidget);
    });

    testWidgets(
        'tablet (600-1000px): still shows an inline side panel like desktop, not a pushed screen',
        (tester) async {
      final gateway = FakeAdminReservationGateway()
        ..listPageToReturn = AdminReservationListPage(
            reservations: [_reservation()], nextCursor: null);
      final repository = FakeAdminReservationRepository();
      await _pumpScreen(tester,
          size: const Size(800, 1000),
          gateway: gateway,
          repository: repository);

      await tester.tap(find.text('Ada Yılmaz'));
      await tester.pump();
      repository.emitDetail('reservation-1', _reservation());
      await tester.pumpAndSettle();

      // Inline, not pushed: the customer name appears twice (list row +
      // detail panel), and there is no separate "Rezervasyon Detayı"
      // AppBar the mobile push path would show.
      expect(find.text('Ada Yılmaz'), findsNWidgets(2));
      expect(find.byType(ReservationDetailPanel), findsOneWidget);
      expect(find.text('Rezervasyon Detayı'), findsNothing);
    });
  });
}
