import '../../data/customer_repository.dart';
import '../../domain/segmentation/customer.dart';
import 'register_customer.dart';

/// Resolves the signed-in app user's [Customer] record — Sprint 5E's
/// customer identity bridge (`docs/decisions.md` ADR-022). The **only**
/// place a phone number is used as an identity *lookup key* in this
/// feature; [Customer.id] (issued by [RegisterCustomer]'s existing
/// `CustomerIdGenerator`) remains the actual, permanent identity — phone
/// number is never stored or treated as that permanent id, satisfying
/// "avoid phone number as the only permanent identity."
///
/// Idempotent: calling this twice with the same [phoneNumber] returns the
/// same [Customer] (same [Customer.id]) both times — the second call
/// finds the record the first call created, it never registers a
/// duplicate. This is a deliberate stand-in for what a real backend would
/// do with an authenticated user's own issued id (`context.auth.uid`
/// equivalent) — once a backend exists, only this use case's internals
/// change; every caller (`currentCustomerProvider`, etc.) is unaffected.
class ResolveCurrentCustomer {
  const ResolveCurrentCustomer({
    required CustomerRepository repository,
    required RegisterCustomer registerCustomer,
  })  : _repository = repository,
        _registerCustomer = registerCustomer;

  final CustomerRepository _repository;
  final RegisterCustomer _registerCustomer;

  Future<Customer> call({
    required String phoneNumber,
    required String displayName,
    required DateTime now,
  }) async {
    final existing = await _repository.findByPhoneNumber(phoneNumber);
    if (existing != null) return existing;

    return _registerCustomer(
      displayName: displayName,
      phoneNumber: phoneNumber,
      registeredAt: now,
    );
  }
}
