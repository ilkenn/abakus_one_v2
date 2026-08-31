import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../bootstrap/firebase_ready_provider.dart';
import '../../../admin/domain/trusted_device/device_registration_state.dart';
import '../../../admin/presentation/providers/trusted_device_session_providers.dart';
import '../../data/cash_register_gateway.dart';
import '../../data/fiscal_offline_gateway.dart';
import '../../data/payment_gateway.dart';
import '../../data/pos_action_gateway.dart';
import '../../data/pos_operational_view_gateway.dart';

/// AP-3 continuation — POS workspace provider wiring, gated end-to-end on
/// the real trusted-device session (`docs/decisions.md` ADR-041). No
/// provider here ever fabricates a `PosDeviceContext` — it only exists once
/// [trustedDeviceSessionControllerProvider] genuinely reports
/// [ActiveSession]/[ExpiringRefreshing].

final posOperationalViewGatewayProvider =
    Provider<PosOperationalViewGateway>((ref) {
  final isFirebaseReady = ref.watch(firebaseReadyProvider);
  if (isFirebaseReady) return const FirebasePosOperationalViewGateway();
  return const UnavailablePosOperationalViewGateway();
});

final posActionGatewayProvider = Provider<PosActionGateway>((ref) {
  final isFirebaseReady = ref.watch(firebaseReadyProvider);
  if (isFirebaseReady) return const FirebasePosActionGateway();
  return const UnavailablePosActionGateway();
});

/// AP-4 Wave D wiring — the real payment/cash/fiscal boundaries, gated on
/// Firebase readiness exactly like every gateway above. Never falls back to
/// an in-memory/mock implementation that could silently fabricate a money
/// result — see each `Unavailable*Gateway`'s own fail-closed doc comment.
final paymentGatewayProvider = Provider<PaymentGateway>((ref) {
  final isFirebaseReady = ref.watch(firebaseReadyProvider);
  if (isFirebaseReady) return const FirebasePaymentGateway();
  return const UnavailablePaymentGateway();
});

final cashRegisterGatewayProvider = Provider<CashRegisterGateway>((ref) {
  final isFirebaseReady = ref.watch(firebaseReadyProvider);
  if (isFirebaseReady) return const FirebaseCashRegisterGateway();
  return const UnavailableCashRegisterGateway();
});

final fiscalOfflineGatewayProvider = Provider<FiscalOfflineGateway>((ref) {
  final isFirebaseReady = ref.watch(firebaseReadyProvider);
  if (isFirebaseReady) return const FirebaseFiscalOfflineGateway();
  return const UnavailableFiscalOfflineGateway();
});

/// `null` until a real trusted-device session is active — every POS screen
/// must treat `null` as "show the trusted-device gate," never attempt a
/// device-gated call with a placeholder context.
final posDeviceContextProvider = Provider<PosDeviceContext?>((ref) {
  final args = ref.watch(currentTrustedDeviceSessionControllerProvider);
  if (args == null) return null;
  final state = ref.watch(trustedDeviceSessionControllerProvider(args));
  return switch (state) {
    ActiveSession(:final deviceId, :final sessionId) => PosDeviceContext(
        organizationId: args.organizationId,
        branchId: args.branchId,
        deviceId: deviceId,
        deviceSessionId: sessionId,
      ),
    ExpiringRefreshing(:final deviceId, :final sessionId) => PosDeviceContext(
        organizationId: args.organizationId,
        branchId: args.branchId,
        deviceId: deviceId,
        deviceSessionId: sessionId,
      ),
    _ => null,
  };
});

/// Currently selected table (branch overview -> table workspace
/// navigation) — `null` while on the branch overview itself.
final selectedPosTableIdProvider = StateProvider<String?>((ref) => null);
