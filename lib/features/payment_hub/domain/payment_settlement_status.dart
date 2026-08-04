/// A [PaymentSettlementRecord]'s lifecycle — Phase 8
/// (`docs/decisions.md` ADR-025). [received] is the initial state (a
/// raw settlement notification arrived, not yet reconciled against
/// this app's own records); [reconciled] means a human/future
/// automated process confirmed it matches; [disputed] means it did not.
enum PaymentSettlementStatus { received, reconciled, disputed }
