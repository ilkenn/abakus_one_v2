import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../data/kitchen_ticket_repository.dart';
import '../../domain/kitchen/kitchen_ticket.dart';

/// Marks one [KitchenTicketLine] ready on a fired [KitchenTicket] — the
/// KDS's product-level completion action. Idempotent (marking an
/// already-ready line ready again is a no-op, no new revision).
///
/// Once every line is ready, [KitchenTicket.orderReadyAt] is set — the
/// order-level readiness the expeditor phase reads — set only once
/// (a line later un-marked isn't modeled; there is no "unmark" action
/// this sprint).
///
/// Throws [UnknownRestaurantOperationsEntityViolation] if [ticketId]
/// doesn't resolve, or (naming the line instead) if [lineId] isn't one of
/// the ticket's own lines.
class MarkKitchenTicketLineReady {
  const MarkKitchenTicketLineReady({
    required Clock clock,
    required KitchenTicketRepository repository,
  })  : _clock = clock,
        _repository = repository;

  final Clock _clock;
  final KitchenTicketRepository _repository;

  Future<KitchenTicket> call({
    required String ticketId,
    required String lineId,
  }) async {
    final ticket = await _repository.findById(ticketId);
    if (ticket == null) {
      throw UnknownRestaurantOperationsEntityViolation(
        entityName: 'KitchenTicket',
        id: ticketId,
      );
    }
    if (!ticket.lines.any((line) => line.id == lineId)) {
      throw UnknownRestaurantOperationsEntityViolation(
        entityName: 'KitchenTicketLine',
        id: lineId,
      );
    }
    if (ticket.completedLineIds.contains(lineId)) return ticket;

    final completed = [...ticket.completedLineIds, lineId];
    final isFullyReady =
        ticket.lines.every((line) => completed.contains(line.id));

    final updated = ticket.copyWith(
      completedLineIds: completed,
      orderReadyAt: isFullyReady ? _clock.now() : null,
      revision: ticket.revision + 1,
    );
    await _repository.save(updated);
    return updated;
  }
}
