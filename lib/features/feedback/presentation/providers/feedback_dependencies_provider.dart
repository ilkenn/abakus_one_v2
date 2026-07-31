import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/identity/customer_feedback_id_generator.dart';
import '../../application/identity/customer_feedback_response_id_generator.dart';
import '../../application/identity/customer_feedback_status_event_id_generator.dart';
import '../../data/customer_feedback_repository.dart';
import '../../data/customer_feedback_response_repository.dart';
import '../../data/customer_feedback_status_event_repository.dart';

/// Central Riverpod wiring for `features/feedback` — mirrors
/// `crm_dependencies_provider.dart`'s shape.

final customerFeedbackRepositoryProvider =
    Provider<CustomerFeedbackRepository>((ref) {
  return InMemoryCustomerFeedbackRepository();
});

final customerFeedbackStatusEventRepositoryProvider =
    Provider<CustomerFeedbackStatusEventRepository>((ref) {
  return InMemoryCustomerFeedbackStatusEventRepository();
});

final customerFeedbackResponseRepositoryProvider =
    Provider<CustomerFeedbackResponseRepository>((ref) {
  return InMemoryCustomerFeedbackResponseRepository();
});

final customerFeedbackIdGeneratorProvider =
    Provider<CustomerFeedbackIdGenerator>((ref) {
  return SequentialCustomerFeedbackIdGenerator();
});

final customerFeedbackStatusEventIdGeneratorProvider =
    Provider<CustomerFeedbackStatusEventIdGenerator>((ref) {
  return SequentialCustomerFeedbackStatusEventIdGenerator();
});

final customerFeedbackResponseIdGeneratorProvider =
    Provider<CustomerFeedbackResponseIdGenerator>((ref) {
  return SequentialCustomerFeedbackResponseIdGenerator();
});
