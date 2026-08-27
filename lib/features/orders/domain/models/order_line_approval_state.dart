import 'dine_in_counter_proposal.dart';
import 'dine_in_line_status.dart';

/// The staff-approval state for one [Order.lines] entry — AP-3
/// continuation. Deliberately kept OUT of [OrderLine] itself: [OrderLine]'s
/// constructor is private and recomputes its money fields from raw inputs
/// (see `OrderFirestoreMapper`'s own doc comment) — it models a *priced
/// product line*, not an approval workflow. This is a parallel, index-keyed
/// list on [Order] instead (the same "additive field, defaulted for every
/// order that predates it" pattern [Order.selectedBenefitType]/
/// [Order.campaign] already use), matching exactly how the server itself
/// stores these fields: embedded on each raw `orders.lines[i]` map
/// alongside — never inside — the product/price fields
/// `functions/src/dineInCounterProposal.ts` reads/writes.
///
/// [lineIndex] always matches the corresponding position in [Order.lines] —
/// `Order.lines[i]` pairs with the entry in `Order.lineApprovalStates` whose
/// [lineIndex] equals `i` (there is always exactly one entry per line,
/// never fewer/more, once [OrderFirestoreMapper.fromFirestore] has parsed a
/// document — a missing per-line status on the wire defaults to
/// [DineInLineStatus.accepted], never to a missing list entry).
class OrderLineApprovalState {
  const OrderLineApprovalState({
    required this.lineIndex,
    required this.status,
    this.counterProposal,
  });

  final int lineIndex;
  final DineInLineStatus status;

  /// Non-null only while [status] is [DineInLineStatus.proposedChange], or
  /// immediately after a response (briefly [DineInLineStatus.accepted]/
  /// [DineInLineStatus.rejected] with the just-resolved proposal still
  /// attached as history) — `null` for a line that has never received a
  /// proposal.
  final DineInCounterProposal? counterProposal;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is OrderLineApprovalState &&
            other.lineIndex == lineIndex &&
            other.status == status &&
            other.counterProposal == counterProposal);
  }

  @override
  int get hashCode => Object.hash(lineIndex, status, counterProposal);
}
