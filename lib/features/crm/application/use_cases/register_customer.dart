import '../../data/customer_repository.dart';
import '../../domain/segmentation/customer.dart';
import '../identity/customer_id_generator.dart';

/// Registers a new [Customer] — the CRM registry entry point. Deliberately
/// minimal (name + phone only, mirrors `RegisterCourier`'s own "no
/// unnecessary sensitive personal data" discipline); category is never
/// collected at registration — it is always a separate, optional,
/// later choice (see `SetCustomerCategory`).
class RegisterCustomer {
  const RegisterCustomer({
    required CustomerIdGenerator idGenerator,
    required CustomerRepository repository,
  })  : _idGenerator = idGenerator,
        _repository = repository;

  final CustomerIdGenerator _idGenerator;
  final CustomerRepository _repository;

  Future<Customer> call({
    required String displayName,
    required String phoneNumber,
    required DateTime registeredAt,
  }) async {
    final customer = Customer(
      id: _idGenerator.nextCustomerId(),
      displayName: displayName,
      phoneNumber: phoneNumber,
      registeredAt: registeredAt,
      revision: 1,
    );
    await _repository.save(customer);
    return customer;
  }
}
