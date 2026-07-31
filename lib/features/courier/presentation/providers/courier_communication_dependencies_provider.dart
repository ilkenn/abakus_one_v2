import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/identity/courier_message_id_generator.dart';
import '../../application/identity/courier_message_status_event_id_generator.dart';
import '../../data/courier_message_repository.dart';
import '../../data/courier_message_status_event_repository.dart';

/// Courier Communication Center dependencies, split out of
/// `courier_dependencies_provider.dart` (Sprint 5E Part 7,
/// `docs/decisions.md` ADR-022) — self-contained, no cross-sub-domain
/// provider references.
final courierMessageRepositoryProvider =
    Provider<CourierMessageRepository>((ref) {
  return InMemoryCourierMessageRepository();
});

final courierMessageIdGeneratorProvider =
    Provider<CourierMessageIdGenerator>((ref) {
  return SequentialCourierMessageIdGenerator();
});

final courierMessageStatusEventRepositoryProvider =
    Provider<CourierMessageStatusEventRepository>((ref) {
  return InMemoryCourierMessageStatusEventRepository();
});

final courierMessageStatusEventIdGeneratorProvider =
    Provider<CourierMessageStatusEventIdGenerator>((ref) {
  return SequentialCourierMessageStatusEventIdGenerator();
});
