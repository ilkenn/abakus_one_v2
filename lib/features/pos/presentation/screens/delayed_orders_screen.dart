import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/clock_provider.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../domain/kds/kitchen_delay_state.dart';
import '../../domain/kds/kitchen_line_status.dart';
import '../../domain/kitchen/kitchen_ticket.dart';
import '../providers/kds_dependencies_provider.dart';
import '../providers/kitchen_ticket_dependencies_provider.dart';

const _defaultThresholds = KitchenDelayThresholds(
  warningThreshold: Duration(minutes: 10),
  criticalThreshold: Duration(minutes: 20),
);

/// Every active order whose worst-line [KitchenDelayState] is at least
/// warning-level — a filtered read of the same data
/// `KitchenDisplayBoardScreen` shows, sorted worst-first.
class DelayedOrdersScreen extends ConsumerStatefulWidget {
  const DelayedOrdersScreen({super.key, required this.branchId});

  final String branchId;

  @override
  ConsumerState<DelayedOrdersScreen> createState() =>
      _DelayedOrdersScreenState();
}

class _DelayedOrdersScreenState extends ConsumerState<DelayedOrdersScreen> {
  List<({KitchenTicket ticket, KitchenDelayState delay})>? _delayed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final clock = ref.read(clockProvider);
    final now = clock.now();
    final tickets = await ref
        .read(kitchenTicketRepositoryProvider)
        .findActiveByBranch(widget.branchId);
    final workItems = await ref
        .read(kitchenProjectionRepositoryProvider)
        .findByBranch(branchId: widget.branchId);

    final result = <({KitchenTicket ticket, KitchenDelayState delay})>[];
    for (final ticket in tickets) {
      final items = workItems
          .where((i) => i.kitchenTicketId == ticket.id)
          .where((i) =>
              i.status != KitchenLineStatus.cancelled &&
              i.status != KitchenLineStatus.unavailable)
          .toList();
      if (items.isEmpty) continue;

      KitchenDelayState? worst;
      for (final item in items) {
        final delay = KitchenDelayState.compute(
          workItemId: item.id,
          queuedAt: item.queuedAt,
          preparingStartedAt: item.preparingStartedAt,
          readyAt: item.readyAt,
          now: now,
          thresholds: _defaultThresholds,
          channelName: ticket.header.orderTypeLabel,
        );
        if (worst == null || delay.totalDuration > worst.totalDuration) {
          worst = delay;
        }
      }
      if (worst != null && (worst.isWarning || worst.isCritical)) {
        result.add((ticket: ticket, delay: worst));
      }
    }
    result
        .sort((a, b) => b.delay.totalDuration.compareTo(a.delay.totalDuration));

    if (!mounted) return;
    setState(() => _delayed = result);
  }

  @override
  Widget build(BuildContext context) {
    final delayed = _delayed;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Geciken Siparişler'),
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
        child: delayed == null
            ? const LoadingView(message: 'Yükleniyor...')
            : delayed.isEmpty
                ? const EmptyView(
                    icon: Icons.check_circle_outline,
                    message: 'Geciken sipariş yok',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    itemCount: delayed.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final entry = delayed[index];
                      return AppCard(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        borderColor: entry.delay.isCritical
                            ? AppColors.error
                            : AppColors.warning,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(entry.ticket.header.orderNumber,
                                style: AppTypography.bodyLarge),
                            Text(
                              '${entry.delay.totalDuration.inMinutes}dk',
                              style: AppTypography.bodyMedium.copyWith(
                                color: entry.delay.isCritical
                                    ? AppColors.error
                                    : AppColors.warning,
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
