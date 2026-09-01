import 'package:abakus_one_v2/features/pos/application/use_cases/ensure_offline_lease.dart';
import 'package:abakus_one_v2/features/pos/data/fiscal_offline_gateway.dart';
import 'package:abakus_one_v2/features/pos/data/offline_lease_store.dart';
import 'package:abakus_one_v2/features/pos/data/pos_action_gateway.dart';
import 'package:abakus_one_v2/features/pos/domain/offline/held_offline_lease.dart';
import 'package:flutter_test/flutter_test.dart';

class InMemoryOfflineLeaseStore implements OfflineLeaseStore {
  HeldOfflineLease? lease;

  @override
  Future<HeldOfflineLease?> currentLease() async => lease;

  @override
  Future<void> saveLease(HeldOfflineLease value) async => lease = value;

  @override
  Future<int> claimNextDeviceSequence(String leaseId) async => 1;

  @override
  Future<void> recordLocalUsage(String leaseId) async {}

  @override
  Future<void> clearLease() async => lease = null;
}

class FakeFiscalOfflineGateway implements FiscalOfflineGateway {
  int issueCallCount = 0;

  @override
  Future<IssuedOfflineLease> issueOfflineLease({
    required PosDeviceContext ctx,
    int? validityMinutes,
    int? maxTransactionCount,
    int? maxTransactionValueMinorUnits,
  }) async {
    issueCallCount += 1;
    return IssuedOfflineLease(
      leaseId: 'lease-$issueCallCount',
      expiresAt: DateTime.now().add(const Duration(hours: 4)),
      allowedTenderTypes: const ['cash'],
      maxTransactionCount: 10,
      maxTransactionValueMinorUnits: 500000,
      catalogVersion: DateTime.now().toIso8601String(),
    );
  }

  @override
  Future<FiscalOperationResult> recordFiscalOperation({
    required PosDeviceContext ctx,
    required String operationType,
    required int amountMinorUnits,
    required String currencyCode,
    required String idempotencyKey,
    String? checkId,
    String? paymentAttemptId,
    String? refundRequestId,
    String? cashSessionId,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> revokeOfflineLease({
    required String organizationId,
    required String branchId,
    required String leaseId,
    required String reason,
  }) =>
      throw UnimplementedError();
}

const _ctx = PosDeviceContext(
  organizationId: 'org-1',
  branchId: 'branch-1',
  deviceId: 'device-1',
  deviceSessionId: 'session-1',
);

void main() {
  group('EnsureOfflineLease', () {
    test('issues a fresh lease when none is held', () async {
      final gateway = FakeFiscalOfflineGateway();
      final store = InMemoryOfflineLeaseStore();
      final useCase =
          EnsureOfflineLease(fiscalOfflineGateway: gateway, leaseStore: store);

      final lease = await useCase(ctx: _ctx);

      expect(gateway.issueCallCount, 1);
      expect(lease.leaseId, 'lease-1');
      expect(store.lease, isNotNull);
    });

    test('reuses a held lease that is still valid and has capacity', () async {
      final gateway = FakeFiscalOfflineGateway();
      final store = InMemoryOfflineLeaseStore();
      final useCase =
          EnsureOfflineLease(fiscalOfflineGateway: gateway, leaseStore: store);

      final first = await useCase(ctx: _ctx);
      final second = await useCase(ctx: _ctx);

      expect(gateway.issueCallCount, 1);
      expect(second.leaseId, first.leaseId);
    });

    test('renews when the held lease is within the renewal window of expiry',
        () async {
      final gateway = FakeFiscalOfflineGateway();
      final store = InMemoryOfflineLeaseStore();
      store.lease = HeldOfflineLease(
        leaseId: 'about-to-expire',
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        allowedTenderTypes: const ['cash'],
        maxTransactionCount: 10,
        maxTransactionValueMinorUnits: 500000,
        catalogVersion: DateTime.now().toIso8601String(),
        transactionsUsedLocally: 0,
      );
      final useCase = EnsureOfflineLease(
        fiscalOfflineGateway: gateway,
        leaseStore: store,
        renewalWindow: const Duration(minutes: 30),
      );

      final lease = await useCase(ctx: _ctx);

      expect(gateway.issueCallCount, 1);
      expect(lease.leaseId, 'lease-1');
    });

    test('renews when the held lease has no remaining transaction capacity',
        () async {
      final gateway = FakeFiscalOfflineGateway();
      final store = InMemoryOfflineLeaseStore();
      store.lease = HeldOfflineLease(
        leaseId: 'exhausted',
        expiresAt: DateTime.now().add(const Duration(hours: 4)),
        allowedTenderTypes: const ['cash'],
        maxTransactionCount: 5,
        maxTransactionValueMinorUnits: 500000,
        catalogVersion: DateTime.now().toIso8601String(),
        transactionsUsedLocally: 5,
      );
      final useCase =
          EnsureOfflineLease(fiscalOfflineGateway: gateway, leaseStore: store);

      final lease = await useCase(ctx: _ctx);

      expect(gateway.issueCallCount, 1);
      expect(lease.leaseId, 'lease-1');
    });
  });
}
