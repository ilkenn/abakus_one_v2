import '../../../../shared/models/money.dart';
import 'cash_movement_type.dart';

/// One immutable, timestamped cash-drawer movement — **never** mutated or
/// deleted once recorded (`docs/business_rules.md` — no delete
/// operations, all movements immutable). Reversing one means recording a
/// new, offsetting [CashMovement] (`ReverseCashMovement`), linked back via
/// [reversalOfMovementId] — the original entry is untouched.
///
/// [amount] is signed: positive means cash added to the drawer, negative
/// means cash removed. For every type except [CashMovementType.correction]
/// /[CashMovementType.closingDifference], the sign is fixed by
/// [CashMovementType.isInflow] and enforced by `RecordCashMovement` — a
/// caller cannot record a `cashSale` as a negative amount by mistake.
class CashMovement {
  const CashMovement({
    required this.id,
    required this.sessionId,
    required this.drawerId,
    required this.type,
    required this.amount,
    required this.reason,
    required this.actorStaffId,
    required this.timestamp,
    this.reversalOfMovementId,
    this.settlementId,
  });

  /// Externally supplied, like every other identifier in this codebase —
  /// no id-generation mechanism lives on this class.
  final String id;

  final String sessionId;
  final String drawerId;
  final CashMovementType type;
  final Money amount;
  final String reason;
  final String actorStaffId;
  final DateTime timestamp;

  /// The id of the [CashMovement] this one reverses — `null` unless this
  /// movement exists specifically to offset an earlier one.
  final String? reversalOfMovementId;

  /// The id of the `CourierSettlement` this movement was automatically
  /// generated from (Phase 3 Sprint 3F) — `null` for every movement
  /// recorded outside the courier-settlement flow (i.e. every Sprint 3E
  /// movement, unchanged). `docs/business_rules.md` BR-COURIER-011
  /// requires every courier-originated cash movement to trace back to the
  /// settlement that approved it; this field is that trace, additive to
  /// Sprint 3E's `CashMovement` rather than a new type.
  final String? settlementId;
}
