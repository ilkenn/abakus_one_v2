import '../domain/contact/customer_contact_action.dart';

/// Append-only storage for [CustomerContactAction].
abstract interface class CustomerContactActionRepository {
  Future<void> append(CustomerContactAction action);
  Future<List<CustomerContactAction>> findByDeliveryId(String deliveryId);
}

class InMemoryCustomerContactActionRepository
    implements CustomerContactActionRepository {
  final List<CustomerContactAction> _actions = [];

  @override
  Future<void> append(CustomerContactAction action) async {
    _actions.add(action);
  }

  @override
  Future<List<CustomerContactAction>> findByDeliveryId(
      String deliveryId) async {
    return List.unmodifiable(
      _actions.where((a) => a.deliveryId == deliveryId),
    );
  }
}
