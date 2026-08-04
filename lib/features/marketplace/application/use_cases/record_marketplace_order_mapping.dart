import '../../data/marketplace_audit_entry_repository.dart';
import '../../data/marketplace_order_mapping_repository.dart';
import '../../domain/audit/marketplace_audit_entry.dart';
import '../../domain/audit/marketplace_audit_event_type.dart';
import '../../domain/marketplace_order_mapping.dart';
import '../identity/marketplace_order_mapping_id_generator.dart';

/// Records that a raw marketplace order arrived — Phase 8
/// (`docs/decisions.md` ADR-025), "Virtual Restaurant → Order Mapping."
///
/// **A trusted internal primitive, not a screen-facing entry point** —
/// deliberately has no `PosAuthorizationPolicy` dependency of its own,
/// mirroring `RecordStockMovement`/`ConsumeStockForOrder`'s established
/// precedent (Phase 7, `docs/decisions.md` ADR-024): the real caller of
/// this use case is a future webhook handler (Webhook Foundation, 8L),
/// not a human actor whose permission needs checking — "do NOT
/// integrate providers yet" means no such webhook exists yet, so this
/// is genuinely unreachable from production code this phase, exactly
/// like Phase 7O's `ConsumeStockForOrder` before any order-completion
/// trigger existed.
///
/// **Idempotent by [externalOrderId]**: a duplicate call for an order
/// already recorded returns the existing mapping unchanged rather than
/// creating a second record — "do not process the same webhook delivery
/// twice."
class RecordMarketplaceOrderMapping {
  const RecordMarketplaceOrderMapping({
    required MarketplaceOrderMappingIdGenerator idGenerator,
    required MarketplaceOrderMappingRepository repository,
    required MarketplaceAuditEntryRepository auditRepository,
  })  : _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final MarketplaceOrderMappingIdGenerator _idGenerator;
  final MarketplaceOrderMappingRepository _repository;
  final MarketplaceAuditEntryRepository _auditRepository;

  Future<MarketplaceOrderMapping> call({
    required String organizationId,
    required String virtualRestaurantId,
    required String externalOrderId,
    required DateTime receivedAt,
  }) async {
    final existing = await _repository.findByExternalOrderId(externalOrderId);
    if (existing != null) return existing;

    final mapping = MarketplaceOrderMapping(
      id: _idGenerator.nextMarketplaceOrderMappingId(),
      virtualRestaurantId: virtualRestaurantId,
      externalOrderId: externalOrderId,
      receivedAt: receivedAt,
      revision: 1,
    );
    await _repository.save(mapping);

    await _auditRepository.appendEvent(MarketplaceAuditEntry(
      id: '${mapping.id}-audit-received',
      organizationId: organizationId,
      actorId: 'system',
      type: MarketplaceAuditEventType.orderMappingRecorded,
      description: 'Marketplace order "$externalOrderId" received for '
          'virtual restaurant "$virtualRestaurantId"',
      targetEntityId: mapping.id,
      timestamp: receivedAt,
    ));

    return mapping;
  }
}
