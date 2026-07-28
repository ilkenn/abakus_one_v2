import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/price_calculator.dart';
import 'package:abakus_one_v2/features/pos/domain/models/pos_order_session.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';

/// A minimal, valid, empty [PosOrderSession] for use-case/controller tests
/// that need a starting point rather than exercising `StartPosOrder`
/// itself.
PosOrderSession buildTestSession({
  String sessionId = 'session-1',
  DateTime? openedAt,
  String openedByStaffId = 'staff-1',
  String branchId = 'branch-1',
  OrderChannel channel = OrderChannel.dineInStaff,
}) {
  final at = openedAt ?? DateTime(2026, 7, 29, 12, 0);
  return PosOrderSession(
    sessionId: sessionId,
    openedAt: at,
    lastUpdatedAt: at,
    openedByStaffId: openedByStaffId,
    branchId: branchId,
    channel: channel,
    fees: Money.zero(Currency.tryLira),
    tip: Money.zero(Currency.tryLira),
    pricing: PriceCalculator.calculate(lines: const [], currency: Currency.tryLira),
  );
}
