import '../../../../core/utils/clock.dart';
import '../../../orders/domain/models/order.dart';
import '../../data/kitchen_ticket_repository.dart';
import '../../domain/kitchen/kitchen_ticket.dart';
import '../../domain/kitchen/kitchen_ticket_mapper.dart';
import '../../domain/kitchen/kitchen_ticket_print_provider.dart';
import '../../domain/kitchen/kitchen_ticket_type.dart';
import '../identity/kitchen_ticket_id_generator.dart';

/// Builds and fires a new [KitchenTicket] from [order] — covers
/// `KitchenTicketType.initial`/`.delta`/`.cancellation` uniformly (the
/// same use case, not three near-duplicates, since building and
/// persisting the ticket is identical regardless of why it was fired;
/// [type] only changes what's printed on it).
///
/// Always persists the ticket, then attempts to print it — a print
/// failure/unavailability never blocks the ticket from existing in the
/// system (the kitchen screen reads from `KitchenTicketRepository`
/// directly, not from print success).
class FireKitchenTicket {
  const FireKitchenTicket({
    required Clock clock,
    required KitchenTicketIdGenerator idGenerator,
    required KitchenTicketRepository repository,
    required KitchenTicketPrintProvider printProvider,
  })  : _clock = clock,
        _idGenerator = idGenerator,
        _repository = repository,
        _printProvider = printProvider;

  final Clock _clock;
  final KitchenTicketIdGenerator _idGenerator;
  final KitchenTicketRepository _repository;
  final KitchenTicketPrintProvider _printProvider;

  Future<KitchenTicket> call({
    required Order order,
    required KitchenTicketType type,
    required String restaurantName,
    required String branchName,
    String priority = '',
  }) async {
    final ticket = KitchenTicketMapper.fromOrder(
      ticketId: _idGenerator.nextTicketId(),
      order: order,
      type: type,
      restaurantName: restaurantName,
      branchName: branchName,
      firedAt: _clock.now(),
      priority: priority,
    );
    await _repository.save(ticket);
    await _printProvider.print(ticket);
    return ticket;
  }
}
