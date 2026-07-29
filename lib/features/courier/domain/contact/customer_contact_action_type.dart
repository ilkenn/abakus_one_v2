/// A safe, predefined customer-contact action a courier may take —
/// never raw phone/messaging access. [maskedCall] specifically means a
/// masked/relayed call — the courier is never given the customer's real
/// number (no telephony provider exists this phase to route it through;
/// this type exists so the seam is ready).
enum CustomerContactActionType {
  maskedCall,
  statusNotification,
  arrivalNotification,
  failedDeliveryNotification,
  supportEscalation,
}
