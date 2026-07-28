import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/payment_session_repository.dart';

/// The [PaymentSessionRepository] currently in use.
/// [InMemoryPaymentSessionRepository] today — no backend persistence
/// exists yet. Mirrors `posOrderRepositoryProvider`'s existing shape.
final paymentSessionRepositoryProvider =
    Provider<PaymentSessionRepository>((ref) {
  return InMemoryPaymentSessionRepository();
});
