import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bootstrap/firebase_ready_provider.dart';
import 'fcm_registration_service.dart';

/// Faz R.3C/R.3C.1 — gated on [firebaseReadyProvider], mirroring every
/// other real-Firebase-service provider in this codebase
/// (`deviceTokenRepositoryProvider`, `kitchenTicketRepositoryProvider`):
/// [NoOpFcmRegistrationService] whenever Firebase isn't ready (including
/// every `flutter test` run, by default), [FirebaseFcmRegistrationService]
/// once it is. No longer depends on `registerDeviceTokenProvider`
/// (Faz R.3C.1 — real registration now goes through the `registerDeviceToken`
/// Cloud Function callable, not a direct Firestore write).
final fcmRegistrationServiceProvider = Provider<FcmRegistrationService>((ref) {
  final isFirebaseReady = ref.watch(firebaseReadyProvider);
  if (!isFirebaseReady) {
    return const NoOpFcmRegistrationService();
  }
  return FirebaseFcmRegistrationService();
});
