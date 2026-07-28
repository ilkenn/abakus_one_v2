import '../../../../core/utils/clock.dart';
import '../../../../shared/models/currency.dart';
import '../../../../shared/models/money.dart';
import '../../../orders/domain/models/order_channel.dart';
import '../../../orders/domain/pricing/price_calculator.dart';
import '../../domain/models/pos_order_session.dart';

/// Opens a new, empty [PosOrderSession].
class StartPosOrder {
  const StartPosOrder({required Clock clock}) : _clock = clock;

  final Clock _clock;

  /// [sessionId] is externally supplied (see [PosOrderSession]'s own doc
  /// comment) — this use case never generates one.
  PosOrderSession call({
    required String sessionId,
    required String branchId,
    required String openedByStaffId,
    required OrderChannel channel,
    String? tableId,
    String? tableSessionId,
  }) {
    final now = _clock.now();
    return PosOrderSession(
      sessionId: sessionId,
      openedAt: now,
      lastUpdatedAt: now,
      openedByStaffId: openedByStaffId,
      branchId: branchId,
      channel: channel,
      tableId: tableId,
      tableSessionId: tableSessionId,
      fees: Money.zero(Currency.accountingCurrency),
      tip: Money.zero(Currency.accountingCurrency),
      pricing: PriceCalculator.calculate(
        lines: const [],
        currency: Currency.accountingCurrency,
      ),
    );
  }
}
