/// P3A (2026-08-23) — mirrors `functions/src/loyaltyLedger.ts`'s closed
/// `LedgerEntryType` union exactly. [unknown] is a deliberate, explicit
/// fail-safe for a future server-added entry type an older client build
/// doesn't recognize yet — never a crash, never silently treated as a
/// known type.
enum LoyaltyLedgerEntryType {
  orderEarn,
  orderEarnReversal,
  boncukRedemption,
  boncukRedemptionRestore,
  catalogRedemption,
  catalogRedemptionRestore,
  wheelEarn,
  wheelExpiry,
  taskEarn,
  taskReversal,
  adminAdjustment,
  unknown,
}

LoyaltyLedgerEntryType loyaltyLedgerEntryTypeFromWire(String raw) {
  for (final type in LoyaltyLedgerEntryType.values) {
    if (type.name == raw) return type;
  }
  return LoyaltyLedgerEntryType.unknown;
}

/// One customer-safe Boncuk movement row — mirrors
/// `getCustomerLoyaltyHistory.ts`'s `CustomerLoyaltyHistoryRow` contract
/// exactly. Deliberately excludes every internal accounting field
/// (`entitlementDeltaBoncuk`/`spendableDeltaBoncuk`/`debtDeltaBoncuk`,
/// rate/remainder/aggregate snapshots) the backend itself never returns —
/// see that file's own doc comment for the full customer-safe mapping
/// this model represents the Dart side of.
class LoyaltyHistoryEntry {
  const LoyaltyHistoryEntry({
    required this.eventId,
    required this.type,
    required this.displayBoncukDelta,
    required this.debtAppliedBoncuk,
    required this.occurredAt,
    required this.orderId,
  });

  final String eventId;
  final LoyaltyLedgerEntryType type;

  /// The signed Boncuk number the customer should see for this event —
  /// already resolved server-side to the correct one of gross-entitlement-
  /// change vs. actual-spendable-change, depending on entry type.
  final int displayBoncukDelta;

  /// How many of [displayBoncukDelta]'s Boncuk were redirected to pay down
  /// existing debt rather than becoming spendable — `0` when not
  /// applicable (redemption-direction entries, or an earn with no debt).
  final int debtAppliedBoncuk;

  final DateTime occurredAt;
  final String? orderId;
}

class LoyaltyHistoryPage {
  const LoyaltyHistoryPage({required this.entries, required this.nextCursor});

  final List<LoyaltyHistoryEntry> entries;

  /// Opaque — round-tripped back to the next `getCustomerLoyaltyHistory`
  /// call verbatim. `null` means no further page exists.
  final String? nextCursor;

  static const empty = LoyaltyHistoryPage(entries: [], nextCursor: null);
}
