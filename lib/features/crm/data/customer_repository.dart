import '../domain/segmentation/customer.dart';
import '../domain/segmentation/customer_category.dart';

/// Storage for [Customer] records — mutable, mirrors `CourierRepository`.
abstract interface class CustomerRepository {
  Future<void> save(Customer customer);
  Future<Customer?> findById(String customerId);

  /// Every customer, regardless of category — the base query every other
  /// segmentation query filters down from.
  Future<List<Customer>> findAll();

  /// The administrator-filter-by-category requirement — customers whose
  /// [Customer.category] equals [category] exactly.
  Future<List<Customer>> findByCategory(CustomerCategory category);

  /// The identity-bridge lookup key — Sprint 5E. Phone number is never
  /// [Customer.id] itself (see `ResolveCurrentCustomer`'s own doc
  /// comment for why), only how an existing record is found. `null` when
  /// no customer has registered with this phone number yet.
  Future<Customer?> findByPhoneNumber(String phoneNumber);
}

class InMemoryCustomerRepository implements CustomerRepository {
  final Map<String, Customer> _byId = {};

  @override
  Future<void> save(Customer customer) async => _byId[customer.id] = customer;

  @override
  Future<Customer?> findById(String customerId) async => _byId[customerId];

  @override
  Future<List<Customer>> findAll() async {
    return List.unmodifiable(_byId.values);
  }

  @override
  Future<List<Customer>> findByCategory(CustomerCategory category) async {
    return List.unmodifiable(
      _byId.values.where((c) => c.category == category),
    );
  }

  @override
  Future<Customer?> findByPhoneNumber(String phoneNumber) async {
    for (final customer in _byId.values) {
      if (customer.phoneNumber == phoneNumber) return customer;
    }
    return null;
  }
}
