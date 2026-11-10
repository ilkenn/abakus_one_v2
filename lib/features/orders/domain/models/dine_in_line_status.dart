/// A dine-in QR order line's staff-approval state — AP-3 continuation,
/// mirrors `functions/src/dineInCounterProposal.ts`'s own raw
/// `orders.lines[i].status` string vocabulary exactly, never a client-
/// invented value.
///
/// Meaningful only for [OrderChannel.dineInQr] lines that went through
/// staff approval; every other channel's lines, and every dine-in line that
/// predates this feature, default to [accepted] on read (see
/// `OrderFirestoreMapper._lineApprovalStateFromFirestore`'s own doc
/// comment) — a purely additive concept, never retroactively invented for
/// an order that never carried it.
enum DineInLineStatus {
  /// Submitted, awaiting a cashier's accept/reject/replacement-proposal
  /// decision.
  pendingApproval,

  /// A cashier accepted the line as submitted (or the customer accepted a
  /// replacement proposal for it).
  accepted,

  /// A cashier rejected the line outright, or the customer rejected a
  /// replacement proposal for it, or a pending proposal expired unanswered.
  rejected,

  /// A cashier proposed a substitute product/quantity — see
  /// [DineInCounterProposal] for the pending proposal's own snapshot.
  proposedChange,

  /// A manager-approved cancellation of an already-accepted line — the
  /// distinct terminal status `functions/src/checkFinancialAdjustments.ts`
  /// writes (AP-3 Wave 2, never reusing [rejected]). 2026-11-10: missing
  /// here until now, so any order carrying such a line failed to map and
  /// broke every list it appeared in (Admin Siparişler, KDS).
  cancelledAfterAcceptance,
}

DineInLineStatus dineInLineStatusFromWire(String? raw) {
  switch (raw) {
    case 'pendingApproval':
      return DineInLineStatus.pendingApproval;
    case 'rejected':
      return DineInLineStatus.rejected;
    case 'proposedChange':
      return DineInLineStatus.proposedChange;
    case 'cancelledAfterAcceptance':
      return DineInLineStatus.cancelledAfterAcceptance;
    case 'accepted':
    case null:
      // `null` covers every line with no status field at all — see this
      // file's own doc comment.
      return DineInLineStatus.accepted;
    default:
      throw StateError('Unknown dine-in line status "$raw"');
  }
}

String dineInLineStatusToWire(DineInLineStatus status) => status.name;
