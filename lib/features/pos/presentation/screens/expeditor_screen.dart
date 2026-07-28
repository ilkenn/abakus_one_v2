import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/clock_provider.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../orders/domain/fulfillment/package_preparation.dart';
import '../../domain/expeditor/expeditor_entry.dart';
import '../../domain/expeditor/expeditor_projection_builder.dart';
import '../providers/kitchen_ticket_dependencies_provider.dart';
import '../providers/package_preparation_dependencies_provider.dart';

/// Coordination view between product readiness (KDS) and final package
/// readiness — pending vs. ready products, whether the complete order is
/// ready, and how long a ready order has been waiting. Read-only: the
/// expeditor observes; marking things ready happens on the KDS/package
/// screens themselves.
///
/// Current Abaküs configuration needs no separate hot/cold/drink
/// stations — this view is a single list, not station-partitioned.
class ExpeditorScreen extends ConsumerStatefulWidget {
  const ExpeditorScreen({super.key, required this.branchId});

  final String branchId;

  @override
  ConsumerState<ExpeditorScreen> createState() => _ExpeditorScreenState();
}

class _ExpeditorScreenState extends ConsumerState<ExpeditorScreen> {
  List<ExpeditorEntry>? _entries;
  DateTime? _now;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final tickets = await ref
        .read(kitchenTicketRepositoryProvider)
        .findActiveByBranch(widget.branchId);
    final packageRepository = ref.read(packagePreparationRepositoryProvider);
    final packagePreparations = <PackagePreparation>[];
    final seenOrderIds = <String>{};
    for (final ticket in tickets) {
      if (!seenOrderIds.add(ticket.orderId.value)) continue;
      final preparation =
          await packageRepository.findCurrentByOrderId(ticket.orderId);
      if (preparation != null) packagePreparations.add(preparation);
    }

    if (!mounted) return;
    setState(() {
      _entries = ExpeditorProjectionBuilder.build(
        tickets: tickets,
        packagePreparations: packagePreparations,
      );
      _now = ref.read(clockProvider).now();
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Expeditör'),
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
        child: entries == null
            ? const LoadingView(message: 'Durum yükleniyor...')
            : entries.isEmpty
                ? const EmptyView(
                    icon: Icons.checklist_outlined,
                    message: 'Bekleyen sipariş yok',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final waitingMinutes = entry.readySince == null
                          ? null
                          : (_now ?? DateTime.now())
                              .difference(entry.readySince!)
                              .inMinutes;
                      return AppCard(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        borderColor:
                            entry.isOrderReady ? AppColors.success : null,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(entry.orderNumber,
                                    style: AppTypography.bodyLarge),
                                Text(
                                  '${entry.readyLineCount}/${entry.readyLineCount + entry.pendingLineCount} ürün hazır'
                                  '${entry.packageStatus != null ? ' • ${entry.packageStatus!.name}' : ''}',
                                  style: AppTypography.bodySmall
                                      .copyWith(color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                            if (entry.isOrderReady)
                              Text(
                                waitingMinutes == null
                                    ? 'HAZIR'
                                    : 'HAZIR • ${waitingMinutes}dk',
                                style: AppTypography.bodyMedium.copyWith(
                                  color: AppColors.success,
                                  fontWeight: FontWeight.bold,
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
