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
}
