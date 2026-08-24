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
import 'package:abakus_one_v2/features/reservation/presentation/screens/reservation_confirmation_screen.dart';

/// Boncuk Loyalty Program P6-B (2026-08-24) — `ReservationConfirmationScreen`
/// reuses `BoncukSuccessSummary` (made public in P6-B, previously
/// `OrderSuccessScreen`'s own private `_BoncukSuccessSummary`) verbatim when
/// the linked preorder order carries a server-confirmed redemption. Mirrors
/// `order_success_screen_test.dart`'s own minimal-fixture-per-test shape.
class _FakeReservationRepository implements ReservationRepository {
  _FakeReservationRepository(this.summary);

  final ReservationSummary? summary;

  @override
  Stream<ReservationSummary?> watchReservation(String reservationId) {
    return Stream.value(summary);
  }
}

class _FakeReservationGateway implements ReservationGateway {
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
      areas: [ReservationArea(id: 'area-1', displayName: 'Bahçe')],
    );
  }

  @override
  Future<List<ReservationAvailabilitySlot>> getReservationAvailability({
    required String restaurantId,
    required String branchId,
    required String areaId,
    required String date,
    required int partySize,
  }) async =>
      const [];

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
    String? selectedRewardId,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> respondToProposedChange({
    required String reservationId,
    required String proposalId,
    required bool accept,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> cancelReservation({
    required String reservationId,
    String? reasonCode,
  }) =>
      throw UnimplementedError();
}

ReservationSummary _summaryWith({ReservationPreorderSummary? preorder}) {
  return ReservationSummary(
    id: 'reservation-1',
    status: ReservationStatus.pendingRestaurantApproval,
    partySize: 2,
    requestedTime: DateTime.utc(2026, 8, 24, 19, 0),
    requestedAreaId: 'area-1',
    preorder: preorder,
  );
}

Future<void> _pumpConfirmation(
  WidgetTester tester,
  ReservationSummary? summary,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        reservationRepositoryProvider
            .overrideWithValue(_FakeReservationRepository(summary)),
        reservationGatewayProvider.overrideWithValue(_FakeReservationGateway()),
      ],
      child: const MaterialApp(
        home: ReservationConfirmationScreen(reservationId: 'reservation-1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'no preorder at all -> no Boncuk summary, no crash on the plain '
      'confirmation copy', (tester) async {
    await _pumpConfirmation(tester, _summaryWith());

    expect(find.byKey(const Key('orderSuccessBoncukSummary')), findsNothing);
    expect(
      find.text('Rezervasyon talebiniz restorana iletildi.'),
      findsOneWidget,
    );
  });

  testWidgets(
      'a preorder with no Boncuk redemption -> "Ön sipariş eklendi" shown, '
      'still no Boncuk summary', (tester) async {
    await _pumpConfirmation(
      tester,
      _summaryWith(
        preorder: const ReservationPreorderSummary(
          orderId: 'order-1',
          status: ReservationPreorderStatus.pendingConfirmation,
          kitchenReleaseAt: null,
          lines: [],
          grandTotalMinorUnits: 24000,
        ),
      ),
    );

    expect(find.text('Ön sipariş eklendi'), findsOneWidget);
    expect(find.byKey(const Key('orderSuccessBoncukSummary')), findsNothing);
  });

  testWidgets(
      'a preorder with a server-confirmed Boncuk redemption -> the reused '
      'BoncukSuccessSummary is shown with the exact server values',
      (tester) async {
    await _pumpConfirmation(
      tester,
      _summaryWith(
        preorder: const ReservationPreorderSummary(
          orderId: 'order-1',
          status: ReservationPreorderStatus.pendingConfirmation,
          kitchenReleaseAt: null,
          lines: [],
          grandTotalMinorUnits: 24000,
          boncukUsed: 2,
          boncukValueMinorUnits: 300,
          remainingPayableMinorUnits: 23700,
        ),
      ),
    );

    expect(find.byKey(const Key('orderSuccessBoncukSummary')), findsOneWidget);
    expect(find.text('2 Boncuk kullanıldı'), findsOneWidget);
    expect(find.text('240 TL'), findsOneWidget);
    expect(find.text('3 TL'), findsOneWidget);
    expect(find.text('237 TL'), findsOneWidget);
  });

  testWidgets(
      'Boncuk Loyalty P7-D (2026-08-24): a preorder with a server-confirmed '
      'catalog reward -> CatalogRewardSuccessSummary is shown with the exact '
      'server values, the product name resolved from the preorder\'s own lines',
      (tester) async {
    await _pumpConfirmation(
      tester,
      _summaryWith(
        preorder: const ReservationPreorderSummary(
          orderId: 'order-1',
          status: ReservationPreorderStatus.pendingConfirmation,
          kitchenReleaseAt: null,
          lines: [
            ReservationPreorderLineSummary(
              productId: 'prod-poke-bowl',
              productName: 'Poke Bowl',
              quantity: 1,
              modifierNames: [],
              lineTotalMinorUnits: 0,
            ),
          ],
          grandTotalMinorUnits: 0,
          catalogRewardTitle: 'Poke Bowl Ödülü',
          catalogRewardBoncukCost: 150,
          catalogRewardRedeemedProductId: 'prod-poke-bowl',
          catalogRewardCoveredValueMinorUnits: 24000,
        ),
      ),
    );

    expect(find.byKey(const Key('orderSuccessCatalogRewardSummary')),
        findsOneWidget);
    expect(find.text('Poke Bowl Ödülü ödülü kullanıldı'), findsOneWidget);
    // No Boncuk cash-redemption summary alongside it — the two are mutually
    // exclusive server-confirmed states, never shown together.
    expect(find.byKey(const Key('orderSuccessBoncukSummary')), findsNothing);
  });
}
