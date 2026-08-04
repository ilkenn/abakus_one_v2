/// A [WebhookDeliveryRecord]'s lifecycle — Phase 8 (`docs/decisions.md`
/// ADR-025). [received] is the initial state; [processed] means the
/// event was successfully applied (e.g. turned into a
/// `MarketplaceOrderMapping`/`PaymentSettlementRecord`); [failed] means
/// processing raised an error; [ignored] means the event type is
/// recognized but this app deliberately takes no action on it.
enum WebhookDeliveryStatus { received, processed, failed, ignored }
