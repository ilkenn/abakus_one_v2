import '../../../../core/errors/business_rule_violation.dart';
import '../../data/check_repository.dart';
import '../../domain/models/check.dart';

/// Adds a guest to an existing [Check] — a table visit's checks may each
/// independently gain guests as the party grows or splits (`Check.
/// withGuestAdded`, idempotent).
///
/// Throws [UnknownRestaurantOperationsEntityViolation] if [checkId]
/// doesn't resolve.
class AddGuestToCheck {
  const AddGuestToCheck({required CheckRepository repository})
      : _repository = repository;

  final CheckRepository _repository;

  Future<Check> call({
    required String checkId,
    required String guestSessionId,
  }) async {
    final check = await _repository.findById(checkId);
    if (check == null) {
      throw UnknownRestaurantOperationsEntityViolation(
        entityName: 'Check',
        id: checkId,
      );
    }
    final updated = check.withGuestAdded(guestSessionId);
    await _repository.save(updated);
    return updated;
  }
}
