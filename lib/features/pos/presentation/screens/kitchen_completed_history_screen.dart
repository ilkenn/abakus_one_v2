import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../domain/kds/kitchen_line_status.dart';
import '../../domain/kds/kitchen_work_item.dart';
import '../providers/kds_dependencies_provider.dart';

/// Every completed ([KitchenLineStatus.ready]) or terminally-closed
/// ([KitchenLineStatus.cancelled]/[KitchenLineStatus.unavailable])
/// [KitchenWorkItem] for a branch — "Completed/Ready History." Reads
/// directly from [KitchenProjectionRepository], never a second, duplicated
/// history record.
class KitchenCompletedHistoryScreen extends ConsumerStatefulWidget {
  const KitchenCompletedHistoryScreen({super.key, required this.branchId});

  final String branchId;

  @override
  ConsumerState<KitchenCompletedHistoryScreen> createState() =>
      _KitchenCompletedHistoryScreenState();
}

class _KitchenCompletedHistoryScreenState
    extends ConsumerState<KitchenCompletedHistoryScreen> {
  List<KitchenWorkItem>? _completed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final items = await ref
        .read(kitchenProjectionRepositoryProvider)
        .findByBranch(branchId: widget.branchId);
    final completed = items
        .where((i) =>
            i.status == KitchenLineStatus.ready ||
            i.status == KitchenLineStatus.cancelled ||
            i.status == KitchenLineStatus.unavailable ||
            i.status == KitchenLineStatus.wasted)
        .toList()
      ..sort((a, b) {
        final aAt = a.readyAt ?? a.cancelledAt ?? a.unavailableAt ?? a.queuedAt;
        final bAt = b.readyAt ?? b.cancelledAt ?? b.unavailableAt ?? b.queuedAt;
        return bAt.compareTo(aAt);
      });
    if (!mounted) return;
    setState(() => _completed = completed);
  }

  @override
  Widget build(BuildContext context) {
    final completed = _completed;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Tamamlanan Geçmişi'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Yenile',
            onPressed: _load,
          ),
        ],
      ),
      body: SafeArea(
        child: completed == null
            ? const LoadingView(message: 'Yükleniyor...')
            : completed.isEmpty
                ? const EmptyView(
                    icon: Icons.done_all_outlined,
                    message: 'Henüz tamamlanan sipariş yok',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    itemCount: completed.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final item = completed[index];
                      return AppCard(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(item.kitchenTicketLineId,
                                style: AppTypography.bodyMedium),
                            Text(
                              item.status.name,
                              style: AppTypography.bodySmall.copyWith(
                                color: item.status == KitchenLineStatus.ready
                                    ? AppColors.success
                                    : AppColors.textSecondary,
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
