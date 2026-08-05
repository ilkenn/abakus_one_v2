import '../../data/customer_repository.dart';
import '../../domain/segmentation/customer.dart';
import 'register_customer.dart';

/// Resolves the signed-in app user's [Customer] record — Sprint 9C's
/// canonical customer identity bridge (`docs/decisions.md` ADR-026,
/// superseding Sprint 5E's phone-only ADR-022 version). [uid] — a real
/// Firebase Auth UID from [AuthSession] — is now both the lookup key and,
/// on first resolution, [Customer.id] itself: `Customer.id == AuthSession.uid`
/// for every customer resolved through this use case, closing the identity
/// fragmentation `docs/phase9_architecture_analysis.md` documents.
/// [phoneNumber] remains a verified login attribute stored on the record,
/// never the identity itself — `CustomerRepository.findByPhoneNumber`
/// still exists for legitimate lookup-by-phone needs elsewhere (e.g. staff
/// searching a customer in POS), just not for resolving *this* identity
/// anymore.
///
/// Idempotent: calling this twice with the same [uid] returns the same
/// [Customer] both times — the second call finds the record the first call
/// created, it never registers a duplicate.
class ResolveCurrentCustomer {
  const ResolveCurrentCustomer({
    required CustomerRepository repository,
    required RegisterCustomer registerCustomer,
  })  : _repository = repository,
        _registerCustomer = registerCustomer;

  final CustomerRepository _repository;
  final RegisterCustomer _registerCustomer;

  Future<Customer> call({
    required String uid,
    required String phoneNumber,
    required String displayName,
    required DateTime now,
  }) async {
    final existing = await _repository.findById(uid);
    if (existing != null) return existing;

    return _registerCustomer(
      id: uid,
      displayName: displayName,
      phoneNumber: phoneNumber,
      registeredAt: now,
    );
  }
}
