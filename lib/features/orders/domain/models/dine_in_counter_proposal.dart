import '../../../../shared/models/money.dart';
import 'order_line_modifier_selection.dart';

/// A staff-proposed replacement for one dine-in QR order line — AP-3
/// continuation, mirrors `functions/src/dineInCounterProposal.ts`'s own
/// `CounterProposalSnapshot` field-for-field. An immutable, server-computed
/// snapshot: [proposedUnitPrice]/[proposedLineTotal]/
/// [differenceFromOriginal] are frozen exactly as the server priced them
/// through the same canonical pricing pipeline `submitDineInOrder` itself
/// uses (`buildProductLine`) — never recomputed client-side, and never
/// altered by the customer's eventual accept/reject decision (only [status]
/// and [respondedAt] change on response; every other field stays the
/// original proposal, forever, as an audit record).
///
/// The only real source of an instance is [OrderFirestoreMapper
/// .fromFirestore] parsing a genuine server-written order document — never
/// constructed from local/client state.
class DineInCounterProposal {
  const DineInCounterProposal({
    required this.proposalVersion,
    required this.proposedProductId,
    required this.proposedProductName,
    required this.proposedModifiers,
    required this.proposedQuantity,
    required this.proposedUnitPrice,
    required this.proposedLineTotal,
    required this.differenceFromOriginal,
    required this.reasonCode,
    required this.reasonMessage,
    required this.proposedByStaffUid,
    required this.createdAt,
    required this.expiresAt,
    required this.status,
    this.respondedAt,
  });

  /// Increments by 1 every time a NEW proposal is made for the same line
  /// (e.g. a first proposal is rejected, then a second, different proposal
  /// is made) — never reused across two structurally different proposals.
  final int proposalVersion;

  final String proposedProductId;
  final String proposedProductName;
  final List<OrderLineModifierSelection> proposedModifiers;
  final int proposedQuantity;

  /// Gross (VAT-inclusive) unit price, frozen at proposal time.
  final Money proposedUnitPrice;

  /// The proposed line's total, frozen at proposal time.
  final Money proposedLineTotal;

  /// `proposedLineTotal - <original line's own lineTotal>` — may be
  /// negative (a cheaper substitute) or zero (an equal-price swap), never
  /// assumed positive.
  final Money differenceFromOriginal;

  /// A closed, server-defined reason vocabulary (e.g. `"outOfStock"`,
  /// `"substitution"`) — deliberately an opaque string, mirroring
  /// `CampaignSnapshot.campaignType`'s own "never hardcode the vocabulary
  /// client-side" rule; only [reasonMessage] is meant for direct display.
  final String reasonCode;

  /// The staff-authored, Turkish-language explanation shown to the
  /// customer.
  final String reasonMessage;

  final String proposedByStaffUid;
  final DateTime createdAt;

  /// After this instant, an unanswered proposal is swept to [expired] by
  /// `sweepExpiredDineInCounterProposals` — never client-enforced.
  final DateTime expiresAt;

  /// `"pendingCustomerResponse" | "accepted" | "rejected" | "expired"` —
  /// deliberately an opaque wire vocabulary via [status], parsed into
  /// [DineInCounterProposalStatus] for exhaustive `switch` handling in UI
  /// code.
  final DineInCounterProposalStatus status;

  /// `null` while [status] is [DineInCounterProposalStatus.pending]; set the
  /// instant the customer responds, or the sweep expires it.
  final DateTime? respondedAt;

  bool get isPending => status == DineInCounterProposalStatus.pending;
  bool get isExpired => status == DineInCounterProposalStatus.expired;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is DineInCounterProposal &&
            other.proposalVersion == proposalVersion &&
            other.proposedProductId == proposedProductId &&
            other.proposedQuantity == proposedQuantity &&
            other.proposedLineTotal == proposedLineTotal &&
            other.status == status);
  }

  @override
  int get hashCode => Object.hash(
        proposalVersion,
        proposedProductId,
        proposedQuantity,
        proposedLineTotal,
        status,
      );
}

enum DineInCounterProposalStatus { pending, accepted, rejected, expired }

DineInCounterProposalStatus dineInCounterProposalStatusFromWire(String raw) {
  switch (raw) {
    case 'pendingCustomerResponse':
      return DineInCounterProposalStatus.pending;
    case 'accepted':
      return DineInCounterProposalStatus.accepted;
    case 'rejected':
      return DineInCounterProposalStatus.rejected;
    case 'expired':
      return DineInCounterProposalStatus.expired;
    default:
      throw StateError('Unknown dine-in counter-proposal status "$raw"');
  }
}
