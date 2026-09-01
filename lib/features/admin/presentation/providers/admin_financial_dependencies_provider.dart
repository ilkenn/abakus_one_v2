import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../bootstrap/firebase_ready_provider.dart';
import '../../data/admin_financial_gateway.dart';

/// AP-4 Wave D — mirrors [trustedDeviceGatewayProvider]'s exact gate shape
/// (`admin_dependencies_provider.dart`): no in-memory fallback, an explicit
/// "unavailable" implementation instead, so a missing backend connection
/// surfaces as an honest error state rather than a silently-empty
/// financial list.
final adminFinancialGatewayProvider = Provider<AdminFinancialGateway>((ref) {
  final isFirebaseReady = ref.watch(firebaseReadyProvider);
  if (isFirebaseReady) {
    return const FirebaseAdminFinancialGateway();
  }
  return const UnavailableAdminFinancialGateway();
});
