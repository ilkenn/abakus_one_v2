import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../bootstrap/firebase_ready_provider.dart';
import '../../data/courier_oversight_gateway.dart';

/// ADR-085 stage 6B — the panel's courier oversight (payment-method changes).
final courierOversightGatewayProvider =
    Provider<CourierOversightGateway>((ref) {
  if (!ref.watch(firebaseReadyProvider)) {
    return const UnavailableCourierOversightGateway();
  }
  return FirebaseCourierOversightGateway();
});

final courierPaymentChangesProvider = FutureProvider.autoDispose
    .family<List<CourierPaymentChange>, String>((ref, organizationId) {
  return ref
      .watch(courierOversightGatewayProvider)
      .paymentChanges(organizationId: organizationId);
});

/// Stage 6C-1 — open field alerts; the panel's "Kurye Uyarıları" and its
/// menu badge refresh it every minute ([CourierAlertsRefresher]) — the
/// Windows POS has no push.
final courierOperationalAlertsProvider = FutureProvider.autoDispose
    .family<List<CourierOperationalAlert>, String>((ref, organizationId) {
  return ref
      .watch(courierOversightGatewayProvider)
      .alerts(organizationId: organizationId);
});

/// How often the alert list refreshes.
const courierAlertsRefreshInterval = Duration(minutes: 1);

/// Refreshes [courierOperationalAlertsProvider] every minute while it is on
/// screen; the timer stops with the widget.
class CourierAlertsRefresher extends ConsumerStatefulWidget {
  const CourierAlertsRefresher({
    super.key,
    required this.organizationId,
    required this.child,
  });

  final String organizationId;
  final Widget child;

  @override
  ConsumerState<CourierAlertsRefresher> createState() =>
      _CourierAlertsRefresherState();
}

class _CourierAlertsRefresherState
    extends ConsumerState<CourierAlertsRefresher> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(courierAlertsRefreshInterval, (_) {
      ref.invalidate(courierOperationalAlertsProvider(widget.organizationId));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
