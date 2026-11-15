import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../bootstrap/firebase_ready_provider.dart';
import '../../data/manager_oversight_gateway.dart';

/// ADR-085 stage 6C-2 — "Müdür İşlemleri" (admin/owner only).
final managerOversightGatewayProvider =
    Provider<ManagerOversightGateway>((ref) {
  if (!ref.watch(firebaseReadyProvider)) {
    return const UnavailableManagerOversightGateway();
  }
  return FirebaseManagerOversightGateway();
});

/// The latest manager actions of the organization, newest first.
final managerActionAlertsProvider = FutureProvider.autoDispose
    .family<List<ManagerActionAlert>, String>((ref, organizationId) {
  return ref
      .watch(managerOversightGatewayProvider)
      .alerts(organizationId: organizationId);
});
