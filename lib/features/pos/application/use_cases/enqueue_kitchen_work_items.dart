import '../../../../core/utils/clock.dart';
import '../../data/kitchen_projection_repository.dart';
import '../../data/kitchen_routing_rule_repository.dart';
import '../../domain/kds/kitchen_event_type.dart';
import '../../domain/kds/kitchen_line_status.dart';
import '../../domain/kds/kitchen_routing_resolver.dart';
import '../../domain/kds/kitchen_work_item.dart';
import '../../domain/kitchen/kitchen_ticket.dart';
import '../identity/kitchen_work_item_id_generator.dart';
import 'record_kitchen_event.dart';

/// Per-line routing input a caller may supply — `KitchenTicketLine` itself
/// carries no `productId`/category (only a frozen display snapshot), so
/// this is deliberately caller-supplied rather than re-derived from the
/// ticket. Omitted entries route to `KitchenStation.shared` (the default).
typedef KitchenRoutingHint = ({
  String? productId,
  String? categoryId,
  Set<String> modifierCodes,
  String? channelName,
});

/// Enqueues one [KitchenWorkItem] per line on a freshly fired
/// [KitchenTicket], routed via [KitchenRoutingResolver] against the
/// branch's [KitchenRoutingRule]s (Phase 4D).
///
/// **Idempotent per (ticket, line)**: `idempotencyKey =
/// '<kitchenTicketId>-<kitchenTicketLineId>'` — a line that already has a
/// work item is skipped rather than re-enqueued, so a duplicate delta
/// fire/retry never creates duplicate kitchen work (Phase 4E's explicit
/// requirement).
class EnqueueKitchenWorkItems {
  const EnqueueKitchenWorkItems({
    required Clock clock,
    required KitchenWorkItemIdGenerator idGenerator,
    required KitchenProjectionRepository projectionRepository,
    required KitchenRoutingRuleRepository routingRuleRepository,
    required RecordKitchenEvent recordKitchenEvent,
  })  : _clock = clock,
        _idGenerator = idGenerator,
        _projectionRepository = projectionRepository,
        _routingRuleRepository = routingRuleRepository,
        _recordKitchenEvent = recordKitchenEvent;

  final Clock _clock;
  final KitchenWorkItemIdGenerator _idGenerator;
  final KitchenProjectionRepository _projectionRepository;
  final KitchenRoutingRuleRepository _routingRuleRepository;
  final RecordKitchenEvent _recordKitchenEvent;

  Future<List<KitchenWorkItem>> call({
    required KitchenTicket ticket,
    Map<String, KitchenRoutingHint> routingHintsByLineId = const {},
  }) async {
    final rules = await _routingRuleRepository.findByBranchId(ticket.branchId);
    final now = _clock.now();
    final created = <KitchenWorkItem>[];

    for (final line in ticket.lines) {
      final idempotencyKey = '${ticket.id}-${line.id}';
      final existing =
          await _projectionRepository.findByIdempotencyKey(idempotencyKey);
      if (existing != null) continue;

      final hint = routingHintsByLineId[line.id];
      final station = KitchenRoutingResolver.resolve(
        rules: rules,
        productId: hint?.productId,
        categoryId: hint?.categoryId,
        modifierCodes: hint?.modifierCodes ?? const {},
        channelName: hint?.channelName,
      );

      final item = KitchenWorkItem(
        id: _idGenerator.nextWorkItemId(),
        branchId: ticket.branchId,
        station: station,
        orderId: ticket.orderId,
        kitchenTicketId: ticket.id,
        kitchenTicketLineId: line.id,
        quantity: line.quantity,
        status: KitchenLineStatus.queued,
        queuedAt: now,
        revision: 1,
        idempotencyKey: idempotencyKey,
      );
      await _projectionRepository.save(item);
      await _recordKitchenEvent(
        branchId: ticket.branchId,
        orderId: ticket.orderId,
        kitchenTicketId: ticket.id,
        workItemId: item.id,
        type: KitchenEventType.workItemQueued,
        idempotencyKey: '$idempotencyKey-queued',
        occurredAt: now,
      );
      created.add(item);
    }

    return created;
  }
}
