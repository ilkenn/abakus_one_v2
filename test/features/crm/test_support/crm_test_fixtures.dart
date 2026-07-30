import 'package:abakus_one_v2/features/crm/domain/segmentation/customer.dart';
import 'package:abakus_one_v2/features/crm/domain/segmentation/customer_category.dart';

/// A minimal, valid [Customer] for use-case tests that need one without
/// exercising `RegisterCustomer` itself.
Customer buildTestCustomer({
  String id = 'customer-1',
  String displayName = 'Test Müşteri',
  String phoneNumber = '+905551112233',
  CustomerCategory? category,
  String? customCategoryLabel,
  int revision = 1,
}) {
  return Customer(
    id: id,
    displayName: displayName,
    phoneNumber: phoneNumber,
    category: category,
    customCategoryLabel: customCategoryLabel,
    registeredAt: DateTime(2026, 1, 1),
    revision: revision,
  );
}
