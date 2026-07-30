import '../../../../core/errors/business_rule_violation.dart';
import '../../data/customer_repository.dart';
import '../../domain/segmentation/customer.dart';
import '../../domain/segmentation/customer_category.dart';

/// Sets or clears a customer's [CustomerCategory] — always the customer's
/// own choice, never an administrator action, so this use case carries no
/// authorization gate (mirrors `SetCourierAvailability`'s self-service
/// shape). [customCategoryLabel] is only kept when [category] is
/// [CustomerCategory.other]; it is silently cleared for every other
/// category so a stale free-text note can never survive a category
/// switch away from "other."
class SetCustomerCategory {
  const SetCustomerCategory({required CustomerRepository repository})
      : _repository = repository;

  final CustomerRepository _repository;

  Future<Customer> call({
    required String customerId,
    CustomerCategory? category,
    String? customCategoryLabel,
  }) async {
    final existing = await _repository.findById(customerId);
    if (existing == null) {
      throw UnknownCrmEntityViolation(entityName: 'Customer', id: customerId);
    }

    final keepsLabel = category == CustomerCategory.other;
    final updated = existing.copyWith(
      category: category,
      clearCategory: category == null,
      customCategoryLabel: keepsLabel ? customCategoryLabel : null,
      clearCustomCategoryLabel: !keepsLabel,
      revision: existing.revision + 1,
    );
    await _repository.save(updated);
    return updated;
  }
}
