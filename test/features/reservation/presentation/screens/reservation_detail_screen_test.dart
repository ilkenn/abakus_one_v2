import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/reservation/data/reservation_gateway.dart';
import 'package:abakus_one_v2/features/reservation/data/reservation_repository.dart';
import 'package:abakus_one_v2/features/reservation/domain/models/reservation_area.dart';
import 'package:abakus_one_v2/features/reservation/domain/models/reservation_availability_slot.dart';
import 'package:abakus_one_v2/features/reservation/domain/models/reservation_branch_info.dart';
import 'package:abakus_one_v2/features/reservation/domain/models/reservation_status.dart';
import 'package:abakus_one_v2/features/reservation/domain/models/reservation_summary.dart';
import 'package:abakus_one_v2/features/reservation/presentation/providers/reservation_dependencies_provider.dart';
import 'package:abakus_one_v2/features/reservation/presentation/screens/reservation_detail_screen.dart';

const _area = ReservationArea(id: 'area-1', displayName: 'Bahçe');

class _FakeReservationRepository implements ReservationRepository {
  final _controller = StreamController<ReservationSummary?>.broadcast();

  void emit(ReservationSummary? summary) => _controller.add(summary);

  @override
  Stream<ReservationSummary?> watchReservation(String reservationId) =>
      _controller.stream;

  void dispose() => _controller.close();
}

class _FakeDetailGateway implements ReservationGateway {
  int respondCallCount = 0;
  final List<Map<String, dynamic>> respondCalls = [];
  ReservationException? respondError;

  int cancelCallCount = 0;
  final List<Map<String, dynamic>> cancelCalls = [];
  ReservationException? cancelError;

  @override
  Future<void> cancelReservation({
    required String reservationId,
    String? reasonCode,
  }) async {
    cancelCallCount++;
    cancelCalls.add({'reservationId': reservationId, 'reasonCode': reasonCode});
    if (cancelError != null) throw cancelError!;
  }

  @override
  Future<ReservationBranchInfo> getReservationBranchInfo({
    required String restaurantId,
    required String branchId,
  }) async {
    return const ReservationBranchInfo(
      policy: ReservationBranchPolicy(
        maxPartySize: 8,
        slotIntervalMinutes: 30,
        reservationDurationMinutes: 90,
        bookingHorizonDays: 60,
        timezone: 'Europe/Istanbul',
        minimumAdvanceMinutes: 30,
      ),
      areas: [_area],
    );
  }

  @override
  Future<void> respondToProposedChange({
    required String reservationId,
    required String proposalId,
    required bool accept,
  }) async {
    respondCallCount++;
    respondCalls.add({
      'reservationId': reservationId,
      'proposalId': proposalId,
      'accept': accept,
    });
    if (respondError != null) throw respondError!;
  }

  @override
  Future<List<ReservationAvailabilitySlot>> getReservationAvailability({
    required String restaurantId,
    required String branchId,
    required String areaId,
    required String date,
    required int partySize,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<SubmitReservationResult> submitReservation({
    required String submissionKey,
    required String restaurantId,
    required String branchId,
    required String areaId,
    required int partySize,
    required DateTime requestedTime,
    required String contactFirstName,
    required String contactLastName,
    List<ReservationPreorderItem>? preorderItems,
    int requestedBoncukAmount = 0,
  }) {
    throw UnimplementedError();
  }
}

ReservationSummary _baseReservation({
  required ReservationStatus status,
  ReservationProposalSnapshot? activeProposal,
  String? activeProposalId,
  ReservationPreorderSummary? preorder,
}) {
  return ReservationSummary(
    id: 'reservation-1',
    status: status,
    partySize: 2,
    requestedTime: DateTime.utc(2026, 8, 20, 18, 0),
    requestedAreaId: _area.id,
    activeProposalId: activeProposalId,
    activeProposal: activeProposal,
    preorder: preorder,
  );
}

Future<_FakeReservationRepository> _pumpDetail(
  WidgetTester tester, {
  _FakeDetailGateway? gateway,
}) async {
  final repository = _FakeReservationRepository();
  addTearDown(repository.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        reservationRepositoryProvider.overrideWithValue(repository),
        reservationGatewayProvider
            .overrideWithValue(gateway ?? _FakeDetailGateway()),
      ],
      child: const MaterialApp(
        home: ReservationDetailScreen(reservationId: 'reservation-1'),
      ),
    ),
  );
  await tester.pump();
  return repository;
}

void main() {
  testWidgets('shows a loading state before the stream emits', (tester) async {
    await _pumpDetail(tester);
    expect(find.text('Rezervasyon yükleniyor...'), findsOneWidget);
  });

  testWidgets('shows a not-found error when the stream emits null',
      (tester) async {
    final repository = await _pumpDetail(tester);
    repository.emit(null);
    await tester.pump();
    expect(find.text('Rezervasyon bulunamadı.'), findsOneWidget);
  });

  group(
      'status copy — every backend status maps to approved Turkish copy, '
      'never the raw enum name', () {
    final cases = {
      ReservationStatus.pendingRestaurantApproval: 'Restoran onayı bekleniyor',
      ReservationStatus.confirmed: 'Rezervasyonunuz onaylandı',
      ReservationStatus.rejected: 'Rezervasyon talebiniz onaylanmadı',
      ReservationStatus.cancelled: 'Rezervasyon iptal edildi',
      ReservationStatus.completed: 'Rezervasyon tamamlandı',
      ReservationStatus.noShow: 'Rezervasyon gerçekleşmedi',
    };

    for (final entry in cases.entries) {
      testWidgets('${entry.key.name} -> "${entry.value}"', (tester) async {
        final repository = await _pumpDetail(tester);
        repository.emit(_baseReservation(status: entry.key));
        await tester.pump();

        expect(find.text(entry.value), findsOneWidget);
        expect(find.text(entry.key.name), findsNothing);
      });
    }
  });

  testWidgets(
      'an active, non-expired change proposal shows the proposal card with '
      'both from/to times and lets the customer accept it', (tester) async {
    final gateway = _FakeDetailGateway();
    final repository = await _pumpDetail(tester, gateway: gateway);

    final proposal = ReservationProposalSnapshot(
      proposedTime: DateTime.utc(2026, 8, 20, 19, 30),
      proposedAreaId: _area.id,
      customerResponseDeadlineAt: DateTime.now().add(const Duration(hours: 1)),
    );
    repository.emit(_baseReservation(
      status: ReservationStatus.changeProposed,
      activeProposal: proposal,
      activeProposalId: 'proposal-1',
    ));
    await tester.pump();

    expect(find.text('Restoran yeni bir seçenek önerdi'), findsOneWidget);
    expect(find.text('Restoran Önerisi'), findsOneWidget);
    expect(find.text('Öneriyi Kabul Et'), findsOneWidget);
    expect(find.text('Bu Öneriyi Reddet'), findsOneWidget);

    await tester.tap(find.text('Öneriyi Kabul Et'));
    await tester.pump();

    expect(gateway.respondCallCount, 1);
    expect(gateway.respondCalls.single, {
      'reservationId': 'reservation-1',
      'proposalId': 'proposal-1',
      'accept': true,
    });
  });

  testWidgets('rejecting a proposal calls the gateway with accept: false',
      (tester) async {
    final gateway = _FakeDetailGateway();
    final repository = await _pumpDetail(tester, gateway: gateway);

    repository.emit(_baseReservation(
      status: ReservationStatus.changeProposed,
      activeProposal: ReservationProposalSnapshot(
        proposedTime: DateTime.utc(2026, 8, 20, 19, 30),
        proposedAreaId: _area.id,
        customerResponseDeadlineAt:
            DateTime.now().add(const Duration(hours: 1)),
      ),
      activeProposalId: 'proposal-1',
    ));
    await tester.pump();

    await tester.tap(find.text('Bu Öneriyi Reddet'));
    await tester.pump();

    expect(gateway.respondCallCount, 1);
    expect(gateway.respondCalls.single['accept'], false);
    // Rejecting is explicitly not terminal — the reassurance copy is shown.
    expect(
      find.text(
          'Reddederseniz rezervasyonunuz iptal olmaz — restoran yeni bir alternatif önerebilir.'),
      findsOneWidget,
    );
  });

  testWidgets(
      'an expired proposal shows the expiry notice instead of accept/reject buttons',
      (tester) async {
    final repository = await _pumpDetail(tester);

    repository.emit(_baseReservation(
      status: ReservationStatus.changeProposed,
      activeProposal: ReservationProposalSnapshot(
        proposedTime: DateTime.utc(2026, 8, 20, 19, 30),
        proposedAreaId: _area.id,
        customerResponseDeadlineAt:
            DateTime.now().subtract(const Duration(hours: 1)),
      ),
      activeProposalId: 'proposal-1',
    ));
    await tester.pump();

    expect(find.text('Bu öneri için yanıt süresi doldu.'), findsOneWidget);
    expect(find.text('Öneriyi Kabul Et'), findsNothing);
    expect(find.text('Bu Öneriyi Reddet'), findsNothing);
  });

  group('preorder status copy — never the raw Order.status', () {
    testWidgets('cancelled preorder', (tester) async {
      final repository = await _pumpDetail(tester);
      repository.emit(_baseReservation(
        status: ReservationStatus.confirmed,
        preorder: const ReservationPreorderSummary(
          orderId: 'order-1',
          status: ReservationPreorderStatus.cancelled,
          kitchenReleaseAt: null,
          lines: [],
          grandTotalMinorUnits: 0,
        ),
      ));
      await tester.pump();

      expect(find.text('Ön siparişiniz iptal edildi.'), findsOneWidget);
    });

    testWidgets('confirmed preorder — already sent to the kitchen',
        (tester) async {
      final repository = await _pumpDetail(tester);
      repository.emit(_baseReservation(
        status: ReservationStatus.confirmed,
        preorder: const ReservationPreorderSummary(
          orderId: 'order-1',
          status: ReservationPreorderStatus.confirmed,
          kitchenReleaseAt: null,
          lines: [],
          grandTotalMinorUnits: 25000,
        ),
      ));
      await tester.pump();

      expect(find.text('Ön siparişiniz mutfağa iletildi.'), findsOneWidget);
      expect(find.text('250 TL'), findsOneWidget);
    });

    testWidgets(
        'pending preorder with a future kitchenReleaseAt shows the exact release time',
        (tester) async {
      final repository = await _pumpDetail(tester);
      repository.emit(_baseReservation(
        status: ReservationStatus.confirmed,
        preorder: ReservationPreorderSummary(
          orderId: 'order-1',
          status: ReservationPreorderStatus.pendingConfirmation,
          kitchenReleaseAt: DateTime.utc(2026, 8, 20, 17, 45),
          lines: const [],
          grandTotalMinorUnits: 0,
        ),
      ));
      await tester.pump();

      final expectedLocal = DateTime.utc(2026, 8, 20, 17, 45).toLocal();
      final expectedLabel =
          '${expectedLocal.hour.toString().padLeft(2, '0')}:${expectedLocal.minute.toString().padLeft(2, '0')}';
      expect(
        find.text("Ön siparişiniz mutfağa $expectedLabel'da iletilecek."),
        findsOneWidget,
      );
    });

    testWidgets(
        'pending preorder with no kitchenReleaseAt yet (reservation not '
        'confirmed) never claims the preorder itself needs approval',
        (tester) async {
      final repository = await _pumpDetail(tester);
      repository.emit(_baseReservation(
        status: ReservationStatus.pendingRestaurantApproval,
        preorder: const ReservationPreorderSummary(
          orderId: 'order-1',
          status: ReservationPreorderStatus.pendingConfirmation,
          kitchenReleaseAt: null,
          lines: [],
          grandTotalMinorUnits: 0,
        ),
      ));
      await tester.pump();

      expect(
        find.text(
          'Rezervasyonunuz onaylandığında ön siparişinizin mutfağa ne zaman '
          'iletileceğini burada görebilirsiniz.',
        ),
        findsOneWidget,
      );
    });
  });

  group('Faz R.3B §20 — customer self-cancellation', () {
    for (final status in [
      ReservationStatus.pendingRestaurantApproval,
      ReservationStatus.changeProposed,
      ReservationStatus.confirmed,
    ]) {
      testWidgets('${status.name}: the cancel button is shown', (tester) async {
        final repository = await _pumpDetail(tester);
        repository.emit(_baseReservation(status: status));
        await tester.pump();

        expect(find.text('Rezervasyonu İptal Et'), findsOneWidget);
      });
    }

    for (final status in [
      ReservationStatus.rejected,
      ReservationStatus.cancelled,
      ReservationStatus.completed,
      ReservationStatus.noShow,
    ]) {
      testWidgets(
          '${status.name}: the cancel button is never shown — terminal status',
          (tester) async {
        final repository = await _pumpDetail(tester);
        repository.emit(_baseReservation(status: status));
        await tester.pump();

        expect(find.text('Rezervasyonu İptal Et'), findsNothing);
      });
    }

    testWidgets(
        'tapping cancel shows a confirmation dialog; dismissing it '
        'never calls the gateway', (tester) async {
      final gateway = _FakeDetailGateway();
      final repository = await _pumpDetail(tester, gateway: gateway);
      repository.emit(_baseReservation(
          status: ReservationStatus.pendingRestaurantApproval));
      await tester.pump();

      await tester.tap(find.text('Rezervasyonu İptal Et'));
      await tester.pumpAndSettle();
      expect(
          find.text('Bu rezervasyonu iptal etmek istediğinizden emin misiniz?'),
          findsOneWidget);

      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(gateway.cancelCallCount, 0);
    });

    testWidgets(
        'confirming cancellation calls the gateway with the reservationId',
        (tester) async {
      final gateway = _FakeDetailGateway();
      final repository = await _pumpDetail(tester, gateway: gateway);
      repository.emit(_baseReservation(
          status: ReservationStatus.pendingRestaurantApproval));
      await tester.pump();

      await tester.tap(find.text('Rezervasyonu İptal Et'));
      await tester.pumpAndSettle();
      // Two matches at this point: the flat action button (now obscured)
      // and the dialog's own destructive confirm button — both literally
      // read "Rezervasyonu İptal Et"; tap the last one (the dialog's).
      await tester.tap(find.text('Rezervasyonu İptal Et').last);
      await tester.pumpAndSettle();

      expect(gateway.cancelCallCount, 1);
      expect(gateway.cancelCalls.single['reservationId'], 'reservation-1');
    });

    testWidgets(
        'a cutoff-reached rejection shows the exact LOCKED contact-restaurant copy',
        (tester) async {
      final gateway = _FakeDetailGateway()
        ..cancelError = const ReservationException(
          'failed-precondition',
          'customerCancellationCutoffReached',
        );
      final repository = await _pumpDetail(tester, gateway: gateway);
      repository.emit(_baseReservation(status: ReservationStatus.confirmed));
      await tester.pump();

      await tester.tap(find.text('Rezervasyonu İptal Et'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rezervasyonu İptal Et').last);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Rezervasyon saatiniz yaklaştığı için uygulamadan iptal edilemiyor. '
          'Lütfen restoranla iletişime geçin.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'a released-preorder rejection shows the exact LOCKED contact-restaurant copy',
        (tester) async {
      final gateway = _FakeDetailGateway()
        ..cancelError = const ReservationException(
          'failed-precondition',
          'reservationPreorderReleasedToKitchen',
        );
      final repository = await _pumpDetail(tester, gateway: gateway);
      repository.emit(_baseReservation(status: ReservationStatus.confirmed));
      await tester.pump();

      await tester.tap(find.text('Rezervasyonu İptal Et'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rezervasyonu İptal Et').last);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Ön siparişiniz mutfağa iletildiği için rezervasyonunuzu '
          'uygulamadan iptal edemezsiniz. Lütfen restoranla iletişime geçin.',
        ),
        findsOneWidget,
      );
    });
  });
}
