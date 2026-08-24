import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/real_customer_check.dart';
import '../../../../core/services/logging/logging_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/loyalty_gateway.dart';
import '../../domain/models/loyalty_account_snapshot.dart';
import '../../domain/models/loyalty_history_entry.dart';
import '../../domain/models/loyalty_reward.dart';

/// P3A (2026-08-23) — dependency-injection seam for the real,
/// server-authoritative Boncuk Loyalty feature. Mirrors this codebase's
/// established gateway-provider convention
/// (`customerRegistrationGatewayProvider`).
final loyaltyGatewayProvider = Provider<LoyaltyGateway>((ref) {
  return FirebaseLoyaltyGateway(
      loggingService: ref.watch(loggingServiceProvider));
});

/// The customer's real Boncuk snapshot — `spendableBalance`/`boncukDebt`/
/// `earningRemainderMinorUnits`/lifetime counters, all server-authoritative
/// via `getCustomerLoyaltySnapshot`. Mirrors
/// `customerProfileCompletionResultProvider`'s exact defensive shape: an
/// internal `isRealCustomer` guard means this never calls the backend on a
/// guest's behalf, returning [LoyaltyAccountSnapshot.zero] instead — a
/// value the UI layer never actually renders as if it were real, since the
/// screen itself independently checks auth state before ever watching this
/// provider (belt-and-suspenders, not the only guard).
///
/// `autoDispose` — reclaimed once nothing (the Loyalty screen) watches it,
/// so a logout followed by a different customer signing in can never see a
/// stale cached balance; re-fetches fresh the next time the screen opens.
/// Re-fetches automatically on any `authProvider` change (a fresh
/// `ref.watch` inside this builder), and on an explicit
/// `ref.invalidate(loyaltySnapshotProvider)` for pull-to-refresh/retry.
final loyaltySnapshotProvider =
    FutureProvider.autoDispose<LoyaltyAccountSnapshot>((ref) async {
  final authState = ref.watch(authProvider);
  if (!isRealCustomer(authState)) {
    return LoyaltyAccountSnapshot.zero;
  }
  return ref.read(loyaltyGatewayProvider).getSnapshot();
});

/// Boncuk Loyalty Program P7-C (2026-08-24) — the real, server-authoritative
/// Reward Catalog (`getCustomerLoyaltyRewardCatalog`), mirroring
/// [loyaltySnapshotProvider]'s exact shape (`autoDispose`, guest-safe empty
/// list, re-fetches on any `authProvider` change or explicit
/// `ref.invalidate`). Never a mock/local reward source — every consumer
/// (currently `TakeawayCheckoutScreen`) reads real rewards through this
/// provider only.
final loyaltyRewardCatalogProvider =
    FutureProvider.autoDispose<List<LoyaltyReward>>((ref) async {
  final authState = ref.watch(authProvider);
  if (!isRealCustomer(authState)) {
    return const [];
  }
  return ref.read(loyaltyGatewayProvider).getRewardCatalog();
});

/// One page's worth of Boncuk movement history, plus pagination state for
/// "load more." `entries` accumulates across [loadMore] calls; the outer
/// [AsyncValue] (via [LoyaltyHistoryNotifier.build]) represents the FIRST
/// page's own loading/error state, while [isLoadingMore] represents a
/// subsequent page fetch without discarding what's already shown.
class LoyaltyHistoryState {
  const LoyaltyHistoryState({
    required this.entries,
    required this.nextCursor,
    required this.isLoadingMore,
    this.loadMoreFailed = false,
  });

  final List<LoyaltyHistoryEntry> entries;
  final String? nextCursor;
  final bool isLoadingMore;

  /// Set only when a [loadMore] attempt itself failed — the already-loaded
  /// [entries] are always preserved; this never resets to an error screen,
  /// only surfaces a small inline retry affordance for the next page.
  final bool loadMoreFailed;

  bool get hasMore => nextCursor != null;

  static const empty = LoyaltyHistoryState(
    entries: [],
    nextCursor: null,
    isLoadingMore: false,
  );

  LoyaltyHistoryState copyWith({
    List<LoyaltyHistoryEntry>? entries,
    String? nextCursor,
    bool clearNextCursor = false,
    bool? isLoadingMore,
    bool? loadMoreFailed,
  }) {
    return LoyaltyHistoryState(
      entries: entries ?? this.entries,
      nextCursor: clearNextCursor ? null : (nextCursor ?? this.nextCursor),
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      loadMoreFailed: loadMoreFailed ?? false,
    );
  }
}

class LoyaltyHistoryNotifier
    extends AutoDisposeAsyncNotifier<LoyaltyHistoryState> {
  @override
  Future<LoyaltyHistoryState> build() async {
    final authState = ref.watch(authProvider);
    if (!isRealCustomer(authState)) {
      return LoyaltyHistoryState.empty;
    }
    final page = await ref.read(loyaltyGatewayProvider).getHistory();
    return LoyaltyHistoryState(
      entries: page.entries,
      nextCursor: page.nextCursor,
      isLoadingMore: false,
    );
  }

  /// Fetches the next page and appends it — a no-op if already loading, or
  /// if the current page reported no further cursor. Never discards
  /// already-loaded [LoyaltyHistoryState.entries] on failure.
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || current.isLoadingMore || !current.hasMore) return;

    state =
        AsyncData(current.copyWith(isLoadingMore: true, loadMoreFailed: false));
    try {
      final page = await ref
          .read(loyaltyGatewayProvider)
          .getHistory(cursor: current.nextCursor);
      state = AsyncData(
        LoyaltyHistoryState(
          entries: [...current.entries, ...page.entries],
          nextCursor: page.nextCursor,
          isLoadingMore: false,
        ),
      );
    } catch (_) {
      state = AsyncData(
        current.copyWith(isLoadingMore: false, loadMoreFailed: true),
      );
    }
  }
}

/// `autoDispose` for the same logout-safety reason as
/// [loyaltySnapshotProvider].
final loyaltyHistoryProvider = AsyncNotifierProvider.autoDispose<
    LoyaltyHistoryNotifier, LoyaltyHistoryState>(
  LoyaltyHistoryNotifier.new,
);
