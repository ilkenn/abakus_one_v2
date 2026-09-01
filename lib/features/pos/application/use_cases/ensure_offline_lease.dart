import '../../data/fiscal_offline_gateway.dart';
import '../../data/offline_lease_store.dart';
import '../../data/pos_action_gateway.dart';
import '../../domain/offline/held_offline_lease.dart';

/// AP-4 Wave E — acquires (or renews) the device's held offline
/// authorization lease WHILE ONLINE, so a later, unpredictable loss of
/// connectivity has a valid, already-issued lease to capture against.
/// Never called from an offline context — issuance is itself a real
/// Cloud Function call (`issueOfflineLease`), impossible without
/// connectivity by construction.
///
/// A held lease is reused as-is until it's within [renewalWindow] of
/// expiring or has no remaining transaction capacity — never renewed
/// unnecessarily (each real issuance is a real server write).
class EnsureOfflineLease {
  const EnsureOfflineLease({
    required FiscalOfflineGateway fiscalOfflineGateway,
    required OfflineLeaseStore leaseStore,
    this.renewalWindow = const Duration(minutes: 30),
  })  : _fiscalOfflineGateway = fiscalOfflineGateway,
        _leaseStore = leaseStore;

  final FiscalOfflineGateway _fiscalOfflineGateway;
  final OfflineLeaseStore _leaseStore;
  final Duration renewalWindow;

  Future<HeldOfflineLease> call({required PosDeviceContext ctx}) async {
    final current = await _leaseStore.currentLease();
    if (current != null &&
        current.hasRemainingCapacity &&
        DateTime.now().isBefore(current.expiresAt.subtract(renewalWindow))) {
      return current;
    }

    final issued = await _fiscalOfflineGateway.issueOfflineLease(ctx: ctx);
    final held = HeldOfflineLease(
      leaseId: issued.leaseId,
      expiresAt: issued.expiresAt,
      allowedTenderTypes: issued.allowedTenderTypes,
      maxTransactionCount: issued.maxTransactionCount,
      maxTransactionValueMinorUnits: issued.maxTransactionValueMinorUnits,
      catalogVersion: issued.catalogVersion,
      transactionsUsedLocally: 0,
    );
    await _leaseStore.saveLease(held);
    return held;
  }
}
