import '../../../../core/errors/business_rule_violation.dart';
import '../../data/kitchen_ticket_repository.dart';
import '../../domain/authorization/pos_authorization_policy.dart';
import '../../domain/authorization/pos_authorized_action.dart';
import '../../domain/kitchen/kitchen_ticket.dart';
import '../../domain/kitchen/kitchen_ticket_print_provider.dart';

/// Reprints an existing [KitchenTicket] — always marked [KitchenTicket
/// .isCopy], never silently indistinguishable from the original print.
/// Requires [PosAuthorizedAction.reprintOrDuplicateReceipt], per the
/// explicit requirement that reprint/duplicate actions be authorized.
///
/// Throws [UnknownRestaurantOperationsEntityViolation] if [ticketId]
/// doesn't resolve, or [AuthorizationDeniedViolation] if denied.
class ReprintKitchenTicket {
  const ReprintKitchenTicket({
    required PosAuthorizationPolicy authorizationPolicy,
    required KitchenTicketRepository repository,
    required KitchenTicketPrintProvider printProvider,
  })  : _authorizationPolicy = authorizationPolicy,
        _repository = repository,
        _printProvider = printProvider;

  final PosAuthorizationPolicy _authorizationPolicy;
  final KitchenTicketRepository _repository;
  final KitchenTicketPrintProvider _printProvider;

  Future<KitchenTicket> call({
    required String ticketId,
    required String performedByStaffId,
  }) async {
    final ticket = await _repository.findById(ticketId);
    if (ticket == null) {
      throw UnknownRestaurantOperationsEntityViolation(
        entityName: 'KitchenTicket',
        id: ticketId,
      );
    }

    final authResult = await _authorizationPolicy.authorize(
      action: PosAuthorizedAction.reprintOrDuplicateReceipt,
      actorStaffId: performedByStaffId,
      context: {'ticketId': ticketId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(
        actionName: PosAuthorizedAction.reprintOrDuplicateReceipt.name,
      );
    }

    final copy = ticket.copyWith(isCopy: true, revision: ticket.revision + 1);
    await _repository.save(copy);
    await _printProvider.print(copy);
    return copy;
  }
}
