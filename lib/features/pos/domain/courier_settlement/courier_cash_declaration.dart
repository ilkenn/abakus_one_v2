import '../../../../shared/models/money.dart';
import 'courier_settlement_variance.dart';

/// One immutable, append-only declaration attempt for a
/// [CourierSettlementSession] — **never overwritten**; a redeclaration
/// after a manager rejection always produces a brand-new
/// [CourierCashDeclaration] with its own [id], mirroring [CashCount]'s
/// same guarantee.
///
/// [expectedAmount] is computed once, at submission time, as the sum of
/// every [CourierCashCollection] recorded for the session so far — frozen
/// here so a later collection can never retroactively change what an
/// already-submitted declaration's expected figure was.
class CourierCashDeclaration {
  const CourierCashDeclaration({
    required this.id,
    required this.settlementSessionId,
    required this.courierId,
    required this.expectedAmount,
    required this.declaredAmount,
    required this.variance,
    required this.declaredAt,
    this.notes = '',
  });

  final String id;
  final String settlementSessionId;
  final String courierId;
  final Money expectedAmount;
  final Money declaredAmount;
  final CourierSettlementVariance variance;
  final DateTime declaredAt;
  final String notes;
}
