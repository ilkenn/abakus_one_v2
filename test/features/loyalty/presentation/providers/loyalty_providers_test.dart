import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/loyalty/data/loyalty_gateway.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_account_snapshot.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_history_entry.dart';
import 'package:abakus_one_v2/features/loyalty/presentation/providers/loyalty_providers.dart';

/// P3A (2026-08-23) — provider tests for the real, server-authoritative
/// Boncuklarım feature. Mirrors
/// `customer_profile_completion_provider_test.dart`'s exact fake-gateway +
/// `SeededAuthNotifier` pattern — no Firestore, no Firebase, a fake
/// gateway standing in for the real callable.
void main() {
  AuthState realCustomerState({String uid = 'customer-uid-1'}) {
    return AuthState(
      isAuthenticated: true,
      isGuest: false,
      session: AuthSession(
        uid: uid,
        phoneNumber: '+905551234567',
        createdAt: DateTime(2026, 1, 1),
        expiresAt: DateTime(2027, 1, 1),
      ),
    );
  }

  ProviderContainer buildContainer({
    AuthState? authState,
    required _FakeLoyaltyGateway gateway,
  }) {
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          () => SeededAuthNotifier(authState ?? realCustomerState()),
        ),
        loyaltyGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('loyaltySnapshotProvider', () {
    test('a guest session never calls the gateway — returns the zero snapshot',
        () async {
      final gateway = _FakeLoyaltyGateway();
      final container = buildContainer(
        authState: const AuthState(isAuthenticated: false, isGuest: true),
        gateway: gateway,
      );

      final snapshot = await container.read(loyaltySnapshotProvider.future);

      expect(snapshot.spendableBalance, 0);
      expect(gateway.snapshotCalls, 0);
    });

    test(
        'a real customer with a fresh zero account sees the real zero snapshot',
        () async {
      final gateway =
          _FakeLoyaltyGateway(snapshot: LoyaltyAccountSnapshot.zero);
      final container = buildContainer(gateway: gateway);

      final snapshot = await container.read(loyaltySnapshotProvider.future);

      expect(snapshot.spendableBalance, 0);
      expect(gateway.snapshotCalls, 1);
    });

    test(
        'a real customer with a non-zero balance sees the real balance — never the old fake 320',
        () async {
      final gateway = _FakeLoyaltyGateway(
        snapshot: const LoyaltyAccountSnapshot(
          spendableBalance: 7,
          boncukDebt: 0,
          earningRemainderMinorUnits: 400,
          minorUnitsUntilNextBoncuk: 600,
          lifetimeEarned: 7,
          lifetimeRedeemed: 0,
          earningSpendMinorUnits: 5000,
          earningBoncukAmount: 5,
          redemptionValueMinorUnitsPerBoncuk: 100,
          maxRedemptionBasisPoints: 5000,
        ),
      );
      final container = buildContainer(gateway: gateway);

      final snapshot = await container.read(loyaltySnapshotProvider.future);

      expect(snapshot.spendableBalance, 7);
      expect(snapshot.spendableBalance, isNot(320));
    });

    test(
        'the earning remainder is exposed exactly as the backend returns it, for progress-bar math',
        () async {
      final gateway = _FakeLoyaltyGateway(
        snapshot: const LoyaltyAccountSnapshot(
          spendableBalance: 0,
          boncukDebt: 0,
          earningRemainderMinorUnits: 400,
          minorUnitsUntilNextBoncuk: 600,
          lifetimeEarned: 0,
          lifetimeRedeemed: 0,
          earningSpendMinorUnits: 5000,
          earningBoncukAmount: 5,
          redemptionValueMinorUnitsPerBoncuk: 100,
          maxRedemptionBasisPoints: 5000,
        ),
      );
      final container = buildContainer(gateway: gateway);

      final snapshot = await container.read(loyaltySnapshotProvider.future);

      expect(snapshot.earningRemainderMinorUnits, 400);
      expect(snapshot.minorUnitsUntilNextBoncuk, 600);
    });

    test(
        'a nonzero debt is exposed — spendableBalance itself is always what the backend reports (never negative, per server-side invariant)',
        () async {
      final gateway = _FakeLoyaltyGateway(
        snapshot: const LoyaltyAccountSnapshot(
          spendableBalance: 0,
          boncukDebt: 7,
          earningRemainderMinorUnits: 0,
          minorUnitsUntilNextBoncuk: 1000,
          lifetimeEarned: 0,
          lifetimeRedeemed: 0,
          earningSpendMinorUnits: 5000,
          earningBoncukAmount: 5,
          redemptionValueMinorUnitsPerBoncuk: 100,
          maxRedemptionBasisPoints: 5000,
        ),
      );
      final container = buildContainer(gateway: gateway);

      final snapshot = await container.read(loyaltySnapshotProvider.future);

      expect(snapshot.boncukDebt, 7);
      expect(snapshot.spendableBalance, 0);
      expect(snapshot.spendableBalance, greaterThanOrEqualTo(0));
    });

    test(
        'a backend failure surfaces as an AsyncError, and invalidating retries',
        () async {
      final gateway = _FakeLoyaltyGateway(
        error: const LoyaltyGatewayException('unavailable', 'boom'),
      );
      final container = buildContainer(gateway: gateway);

      await expectLater(
        container.read(loyaltySnapshotProvider.future),
        throwsA(isA<LoyaltyGatewayException>()),
      );

      gateway.error = null;
      gateway.snapshot = LoyaltyAccountSnapshot.zero;
      container.invalidate(loyaltySnapshotProvider);
      final snapshot = await container.read(loyaltySnapshotProvider.future);
      expect(snapshot.spendableBalance, 0);
    });
  });

  group('loyaltyHistoryProvider', () {
    test('a guest session never calls the gateway — empty history', () async {
      final gateway = _FakeLoyaltyGateway();
      final container = buildContainer(
        authState: const AuthState(isAuthenticated: false, isGuest: true),
        gateway: gateway,
      );

      final state = await container.read(loyaltyHistoryProvider.future);

      expect(state.entries, isEmpty);
      expect(gateway.historyCalls, 0);
    });

    test('no movements yet — empty state, no fake transactions', () async {
      final gateway =
          _FakeLoyaltyGateway(historyPages: [LoyaltyHistoryPage.empty]);
      final container = buildContainer(gateway: gateway);

      final state = await container.read(loyaltyHistoryProvider.future);

      expect(state.entries, isEmpty);
      expect(state.hasMore, isFalse);
    });

    test('a populated first page loads correctly', () async {
      final gateway = _FakeLoyaltyGateway(
        historyPages: [
          LoyaltyHistoryPage(
            entries: [_entry('e1', 10), _entry('e2', 4)],
            nextCursor: null,
          ),
        ],
      );
      final container = buildContainer(gateway: gateway);

      final state = await container.read(loyaltyHistoryProvider.future);

      expect(state.entries, hasLength(2));
      expect(state.hasMore, isFalse);
    });

    test('loadMore appends the next page and preserves already-loaded entries',
        () async {
      final gateway = _FakeLoyaltyGateway(
        historyPages: [
          LoyaltyHistoryPage(
              entries: [_entry('e1', 10)], nextCursor: 'cursor-1'),
          LoyaltyHistoryPage(entries: [_entry('e2', 4)], nextCursor: null),
        ],
      );
      final container = buildContainer(gateway: gateway);

      await container.read(loyaltyHistoryProvider.future);
      await container.read(loyaltyHistoryProvider.notifier).loadMore();

      final state = container.read(loyaltyHistoryProvider).value!;
      expect(state.entries.map((e) => e.eventId), ['e1', 'e2']);
      expect(state.hasMore, isFalse);
      // The first call is the initial `build()` load (cursor null); the
      // second is `loadMore()`'s own call, using the first page's cursor.
      expect(gateway.historyCursors, [null, 'cursor-1']);
    });

    test('loadMore is a no-op when there is no further page', () async {
      final gateway = _FakeLoyaltyGateway(
        historyPages: [
          LoyaltyHistoryPage(entries: [_entry('e1', 10)], nextCursor: null)
        ],
      );
      final container = buildContainer(gateway: gateway);

      await container.read(loyaltyHistoryProvider.future);
      await container.read(loyaltyHistoryProvider.notifier).loadMore();

      expect(gateway.historyCalls, 1,
          reason: 'loadMore must not call the gateway again');
    });

    test(
        'a loadMore failure preserves already-loaded entries and sets loadMoreFailed',
        () async {
      final gateway = _FakeLoyaltyGateway(
        historyPages: [
          LoyaltyHistoryPage(
              entries: [_entry('e1', 10)], nextCursor: 'cursor-1'),
        ],
        failHistoryAfterFirstPage: true,
      );
      final container = buildContainer(gateway: gateway);

      await container.read(loyaltyHistoryProvider.future);
      await container.read(loyaltyHistoryProvider.notifier).loadMore();

      final state = container.read(loyaltyHistoryProvider).value!;
      expect(state.entries, hasLength(1),
          reason: 'existing entries must survive a failed loadMore');
      expect(state.loadMoreFailed, isTrue);
      expect(state.isLoadingMore, isFalse);
    });
  });
}

LoyaltyHistoryEntry _entry(String eventId, int delta) {
  return LoyaltyHistoryEntry(
    eventId: eventId,
    type: LoyaltyLedgerEntryType.orderEarn,
    displayBoncukDelta: delta,
    debtAppliedBoncuk: 0,
    occurredAt: DateTime(2026, 8, 23),
    orderId: null,
  );
}

class _FakeLoyaltyGateway implements LoyaltyGateway {
  _FakeLoyaltyGateway({
    LoyaltyAccountSnapshot? snapshot,
    this.error,
    List<LoyaltyHistoryPage>? historyPages,
    this.failHistoryAfterFirstPage = false,
  })  : snapshot = snapshot ?? LoyaltyAccountSnapshot.zero,
        _historyPages = historyPages ?? [LoyaltyHistoryPage.empty];

  LoyaltyAccountSnapshot snapshot;
  LoyaltyGatewayException? error;
  final List<LoyaltyHistoryPage> _historyPages;
  final bool failHistoryAfterFirstPage;

  int snapshotCalls = 0;
  int historyCalls = 0;
  final List<String?> historyCursors = [];

  @override
  Future<LoyaltyAccountSnapshot> getSnapshot() async {
    snapshotCalls += 1;
    if (error != null) throw error!;
    return snapshot;
  }

  @override
  Future<LoyaltyHistoryPage> getHistory({int? pageSize, String? cursor}) async {
    historyCalls += 1;
    historyCursors.add(cursor);
    if (failHistoryAfterFirstPage && historyCalls > 1) {
      throw const LoyaltyGatewayException('unavailable', 'boom');
    }
    final index = historyCalls - 1;
    return index < _historyPages.length
        ? _historyPages[index]
        : LoyaltyHistoryPage.empty;
  }
}
