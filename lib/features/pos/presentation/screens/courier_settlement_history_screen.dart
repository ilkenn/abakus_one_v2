import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../domain/courier_settlement/courier_settlement_audit_entry.dart';
import '../providers/courier_settlement_dependencies_provider.dart';

/// Every past courier-settlement event for one courier — collections,
/// declarations, approvals, rejections, adjustments, variance decisions,
/// and closures — read from the append-only
/// [CourierSettlementAuditEntry] trail rather than a second, duplicated
/// history record (`docs/business_rules.md` BR-CASH-*'s "never duplicate
/// financial events" principle, extended to courier settlement).
class CourierSettlementHistoryScreen extends ConsumerStatefulWidget {
  const CourierSettlementHistoryScreen({super.key, required this.courierId});

  final String courierId;

  @override
  ConsumerState<CourierSettlementHistoryScreen> createState() =>
      _CourierSettlementHistoryScreenState();
}

class _CourierSettlementHistoryScreenState
    extends ConsumerState<CourierSettlementHistoryScreen> {
  List<CourierSettlementAuditEntry>? _entries;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final entries = await ref
        .read(courierSettlementAuditEntryRepositoryProvider)
        .findByCourierId(widget.courierId);
    if (!mounted) return;
    setState(() => _entries = entries.reversed.toList());
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Vardiya Geçmişi'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: entries == null
            ? const LoadingView(message: 'Geçmiş yükleniyor...')
            : entries.isEmpty
                ? const EmptyView(
                    icon: Icons.history_outlined,
                    message: 'Henüz geçmiş kayıt yok',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return AppCard(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entry.type.name,
                                style: AppTypography.bodyMedium),
                            Text(entry.description,
                                style: AppTypography.bodySmall
                                    .copyWith(color: AppColors.textSecondary)),
                            Text(
                              '${entry.actorStaffId} • ${entry.timestamp}',
                              style: AppTypography.bodySmall
                                  .copyWith(color: AppColors.textSecondary),
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
