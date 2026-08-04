import 'webhook_delivery_status.dart';

/// One incoming webhook delivery from a provider — Phase 8
/// (`docs/decisions.md` ADR-025), the "Webhook" step in both
/// Marketplace Hub's and Payment Hub's own hierarchies.
///
/// **A foundational limitation stated plainly, not glossed over**: a
/// webhook is, by definition, an inbound HTTP request a *server*
/// receives — this codebase has no backend at all (`CLAUDE.md` §3:
/// "Everything is client-side, in-memory mock data — there is no
/// backend"). This record is therefore the domain shape a **future
/// backend** would populate once one exists; nothing in this Flutter
/// client app can ever actually receive a real webhook delivery. This
/// is a more fundamental gap than "no real vendor integration yet"
/// (the honest limitation named throughout the rest of Phase 8) — it's
/// "no server exists to receive one at all."
class WebhookDeliveryRecord {
  const WebhookDeliveryRecord({
    required this.id,
    required this.organizationId,
    required this.providerId,
    required this.externalDeliveryId,
    required this.eventType,
    required this.rawPayload,
    this.signatureVerified = false,
    this.status = WebhookDeliveryStatus.received,
    required this.receivedAt,
    required this.revision,
  });

  final String id;
  final String organizationId;
  final String providerId;

  /// The provider's own opaque delivery identifier — used for
  /// idempotency (a provider may redeliver the same event).
  final String externalDeliveryId;

  /// An opaque, provider-defined event-type string (e.g.
  /// `"order.created"`) — never assumed to follow any particular
  /// naming scheme across providers.
  final String eventType;

  /// The raw request body, stored as-is for replay/debugging — unlike
  /// `IntegrationCredentialRef`/`CustomerPhoto.photoRef`, a webhook
  /// delivery log legitimately needs its payload for reprocessing, the
  /// same reason a real payment gateway's own webhook dashboard stores
  /// raw deliveries. **Stated as a real, unresolved consideration**:
  /// a production deployment would need a retention/PII policy for
  /// this field before storing customer order data indefinitely —
  /// explicitly out of scope for this foundation, not silently ignored.
  final String rawPayload;

  final bool signatureVerified;
  final WebhookDeliveryStatus status;
  final DateTime receivedAt;
  final int revision;

  WebhookDeliveryRecord copyWith({
    WebhookDeliveryStatus? status,
    required int revision,
  }) {
    return WebhookDeliveryRecord(
      id: id,
      organizationId: organizationId,
      providerId: providerId,
      externalDeliveryId: externalDeliveryId,
      eventType: eventType,
      rawPayload: rawPayload,
      signatureVerified: signatureVerified,
      status: status ?? this.status,
      receivedAt: receivedAt,
      revision: revision,
    );
  }
}
