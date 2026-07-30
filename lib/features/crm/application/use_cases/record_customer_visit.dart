import '../../../../core/errors/business_rule_violation.dart';
import '../../data/customer_repository.dart';
import '../../data/customer_visit_repository.dart';
import '../../domain/visits/customer_visit.dart';
import '../identity/customer_visit_id_generator.dart';

/// Records one [CustomerVisit] — "visit counter" foundation of the Visit
/// Passport. A pure recording action: it never computes progress, never
/// grants a reward itself (see `GrantVisitReward`, Sprint 5D Part 3's
/// rewards engine, and `BuildCustomerVisitPassport`, which derives
/// progress/rewards fresh from this history).
class RecordCustomerVisit {
  const RecordCustomerVisit({
    required CustomerVisitIdGenerator idGenerator,
    required CustomerRepository customerRepository,
    required CustomerVisitRepository visitRepository,
  })  : _idGenerator = idGenerator,
        _customerRepository = customerRepository,
        _visitRepository = visitRepository;

  final CustomerVisitIdGenerator _idGenerator;
  final CustomerRepository _customerRepository;
  final CustomerVisitRepository _visitRepository;

  Future<CustomerVisit> call({
    required String customerId,
    required String branchId,
    String? orderId,
    required DateTime occurredAt,
  }) async {
    final customer = await _customerRepository.findById(customerId);
    if (customer == null) {
      throw UnknownCrmEntityViolation(entityName: 'Customer', id: customerId);
    }

    final visit = CustomerVisit(
      id: _idGenerator.nextVisitId(),
      customerId: customerId,
      branchId: branchId,
      orderId: orderId,
      occurredAt: occurredAt,
    );
    await _visitRepository.append(visit);
    return visit;
  }
}
