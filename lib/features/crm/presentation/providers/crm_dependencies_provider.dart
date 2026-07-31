import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/clock_provider.dart';
import '../../application/identity/customer_id_generator.dart';
import '../../application/identity/customer_notification_campaign_id_generator.dart';
import '../../application/identity/customer_reward_grant_id_generator.dart';
import '../../application/identity/customer_visit_id_generator.dart';
import '../../application/identity/survey_id_generator.dart';
import '../../application/identity/survey_response_id_generator.dart';
import '../../application/identity/visit_reward_rule_id_generator.dart';
import '../../application/use_cases/build_customer_visit_passport.dart';
import '../../application/use_cases/build_survey_statistics.dart';
import '../../data/customer_notification_campaign_repository.dart';
import '../../data/customer_repository.dart';
import '../../data/customer_reward_grant_repository.dart';
import '../../data/customer_visit_repository.dart';
import '../../data/survey_repository.dart';
import '../../data/survey_response_repository.dart';
import '../../data/visit_reward_rule_repository.dart';

/// Central Riverpod wiring for `features/crm` — mirrors
/// `courier_dependencies_provider.dart`'s single-large-provider-file
/// shape. Repositories/id-generators are provided so every screen shares
/// the same in-memory store; simple CRUD-shaped use cases are
/// constructed inline in each screen (matches
/// `CourierCommunicationCenterScreen`'s established precedent) — only
/// the cross-cutting read-model builders get their own provider here.

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  return InMemoryCustomerRepository();
});

final customerVisitRepositoryProvider =
    Provider<CustomerVisitRepository>((ref) {
  return InMemoryCustomerVisitRepository();
});

final visitRewardRuleRepositoryProvider =
    Provider<VisitRewardRuleRepository>((ref) {
  return InMemoryVisitRewardRuleRepository();
});

final customerRewardGrantRepositoryProvider =
    Provider<CustomerRewardGrantRepository>((ref) {
  return InMemoryCustomerRewardGrantRepository();
});

final surveyRepositoryProvider = Provider<SurveyRepository>((ref) {
  return InMemorySurveyRepository();
});

final surveyResponseRepositoryProvider =
    Provider<SurveyResponseRepository>((ref) {
  return InMemorySurveyResponseRepository();
});

final customerNotificationCampaignRepositoryProvider =
    Provider<CustomerNotificationCampaignRepository>((ref) {
  return InMemoryCustomerNotificationCampaignRepository();
});

final customerIdGeneratorProvider = Provider<CustomerIdGenerator>((ref) {
  return SequentialCustomerIdGenerator();
});

final customerVisitIdGeneratorProvider =
    Provider<CustomerVisitIdGenerator>((ref) {
  return SequentialCustomerVisitIdGenerator();
});

final visitRewardRuleIdGeneratorProvider =
    Provider<VisitRewardRuleIdGenerator>((ref) {
  return SequentialVisitRewardRuleIdGenerator();
});

final customerRewardGrantIdGeneratorProvider =
    Provider<CustomerRewardGrantIdGenerator>((ref) {
  return SequentialCustomerRewardGrantIdGenerator();
});

final surveyIdGeneratorProvider = Provider<SurveyIdGenerator>((ref) {
  return SequentialSurveyIdGenerator();
});

final surveyResponseIdGeneratorProvider =
    Provider<SurveyResponseIdGenerator>((ref) {
  return SequentialSurveyResponseIdGenerator();
});

final customerNotificationCampaignIdGeneratorProvider =
    Provider<CustomerNotificationCampaignIdGenerator>((ref) {
  return SequentialCustomerNotificationCampaignIdGenerator();
});

final buildCustomerVisitPassportProvider =
    Provider<BuildCustomerVisitPassport>((ref) {
  return BuildCustomerVisitPassport(
    clock: ref.watch(clockProvider),
    visitRepository: ref.watch(customerVisitRepositoryProvider),
    ruleRepository: ref.watch(visitRewardRuleRepositoryProvider),
    grantRepository: ref.watch(customerRewardGrantRepositoryProvider),
  );
});

final buildSurveyStatisticsProvider = Provider<BuildSurveyStatistics>((ref) {
  return BuildSurveyStatistics(
    clock: ref.watch(clockProvider),
    surveyRepository: ref.watch(surveyRepositoryProvider),
    responseRepository: ref.watch(surveyResponseRepositoryProvider),
  );
});
