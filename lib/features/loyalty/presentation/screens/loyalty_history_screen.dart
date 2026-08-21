import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../providers/loyalty_providers.dart';
import '../widgets/loyalty_history_tile.dart';

/// P3A (2026-08-23) — the full, real, paginated Boncuk Movements history.
/// Reuses [loyaltyHistoryProvider] (the same provider the main
/// Boncuklarım screen's preview section watches) so the two never show
/// divergent data — this screen simply renders every loaded entry plus
/// loads further pages, rather than owning a second, separate history
/// fetch.
class LoyaltyHistoryScreen extends ConsumerStatefulWidget {
  const LoyaltyHistoryScreen({super.key});

  @override
  ConsumerState<LoyaltyHistoryScreen> createState() =>
      _LoyaltyHistoryScreenState();
}

class _LoyaltyHistoryScreenState extends ConsumerState<LoyaltyHistoryScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_maybeLoadMore);
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (_scrollController.position.pixels <
        _scrollController.position.maxScrollExtent - 200) {
      return;
    }
    final state = ref.read(loyaltyHistoryProvider).valueOrNull;
    if (state == null || state.isLoadingMore || !state.hasMore) return;
    ref.read(loyaltyHistoryProvider.notifier).loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(loyaltyHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Boncuk Hareketleri'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: historyAsync.when(
          loading: () => const LoadingView(),
          error: (error, stackTrace) => ErrorView(
            message: 'Boncuk geçmişi şu anda yüklenemedi.',
            retryLabel: 'Tekrar Dene',
            onRetry: () => ref.invalidate(loyaltyHistoryProvider),
          ),
          data: (state) {
            if (state.entries.isEmpty) {
              return const EmptyView(
                icon: Icons.history_rounded,
                message: 'Henüz Boncuk hareketin yok.',
              );
            }
            return RefreshIndicator(
              onRefresh: () => ref.refresh(loyaltyHistoryProvider.future),
              child: ListView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  AppCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < state.entries.length; i++) ...[
                          LoyaltyHistoryTile(entry: state.entries[i]),
                          if (i != state.entries.length - 1)
                            const Divider(height: 1, color: AppColors.border),
                        ],
                      ],
                    ),
                  ),
                  if (state.isLoadingMore)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  if (state.loadMoreFailed)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.lg,
                      ),
                      child: Center(
                        child: TextButton(
                          onPressed: () => ref
                              .read(loyaltyHistoryProvider.notifier)
                              .loadMore(),
                          child: const Text(
                              'Daha fazla yüklenemedi · Tekrar dene'),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
