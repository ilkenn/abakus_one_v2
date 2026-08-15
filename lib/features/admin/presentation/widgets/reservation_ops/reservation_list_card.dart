import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../domain/reservations/admin_reservation_summary.dart';
import '../../providers/admin_reservation_detail_provider.dart';
import 'admin_reservation_status_copy.dart';

/// One reservation row — Faz R.3A §2's minimum field set: time, customer
/// name, party size, area, status, table (if assigned), preorder
/// indicator, response urgency. Premium-card, low-color-noise per §1 —
/// one status accent color per card, everything else neutral.
class ReservationListCard extends ConsumerWidget {
  const ReservationListCard(
      {super.key, required this.reservation, required this.onTap});

  final AdminReservationSummary reservation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final areasAsync = ref.watch(adminReservationBranchAreasProvider);
    final areaName = areasAsync.maybeWhen(
      data: (areas) => areas
          .where((a) => a.id == reservation.effectiveAreaId)
          .map((a) => a.displayName)
          .firstOrNull,
      orElse: () => null,
    );
    final time = reservation.effectiveTime.toLocal();
    final timeLabel =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    final statusColor = adminReservationStatusColor(reservation.status);

    final statusChip = Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.1),
          borderRadius: AppRadius.kPill),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(adminReservationStatusIcon(reservation.status),
              size: 12, color: statusColor),
          const SizedBox(width: 4),
          Text(
            adminReservationStatusLabel(reservation.status),
            style: AppTypography.caption
                .copyWith(color: statusColor, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: 48,
          decoration:
              BoxDecoration(color: statusColor, borderRadius: AppRadius.kPill),
        ),
        const SizedBox(width: AppSpacing.md),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(timeLabel, style: AppTypography.titleMedium),
            const SizedBox(height: 2),
            Text(
              '${reservation.partySize} kişi',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                reservation.contactFullName,
                style: AppTypography.bodyLarge
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              // Wrap, not Row — area name + table + preorder badges
              // together can exceed the available width; Wrap flows the
              // overflow badges onto a second line instead of overflowing.
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (areaName != null)
                    _InlineBadge(icon: Icons.deck_rounded, label: areaName),
                  if (reservation.hasAssignedTable)
                    const _InlineBadge(
                        icon: Icons.table_bar_rounded, label: 'Masa'),
                  if (reservation.hasPreorder)
                    const _InlineBadge(
                        icon: Icons.restaurant_rounded, label: 'Ön Sipariş'),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    return Material(
      color: AppColors.surface,
      borderRadius: AppRadius.kMedium,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.kMedium,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: AppRadius.kMedium,
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2))
            ],
          ),
          // A narrow card (small phones) puts the status chip / response
          // urgency BELOW the header instead of beside it — trying to fit
          // time + name + badges + a status chip all in one row is what
          // caused a real overflow on real phone widths; stacking is the
          // robust fix, not shaving pixels off individual elements.
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 420;
              if (!isNarrow) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: header),
                    const SizedBox(width: AppSpacing.sm),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        statusChip,
                        if (reservation
                                .activeProposalCustomerResponseDeadlineAt !=
                            null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          _ResponseUrgencyLabel(
                              deadline: reservation
                                  .activeProposalCustomerResponseDeadlineAt!),
                        ],
                      ],
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      statusChip,
                      if (reservation
                              .activeProposalCustomerResponseDeadlineAt !=
                          null) ...[
                        const SizedBox(width: AppSpacing.sm),
                        _ResponseUrgencyLabel(
                            deadline: reservation
                                .activeProposalCustomerResponseDeadlineAt!),
                      ],
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ResponseUrgencyLabel extends StatelessWidget {
  const _ResponseUrgencyLabel({required this.deadline});

  final DateTime deadline;

  @override
  Widget build(BuildContext context) {
    final remaining = deadline.difference(DateTime.now());
    final expired = remaining.isNegative;
    final label = expired
        ? 'Süresi doldu'
        : remaining.inHours >= 1
            ? '${remaining.inHours} sa kaldı'
            : '${remaining.inMinutes.clamp(0, 59)} dk kaldı';
    return Text(
      label,
      style: AppTypography.caption.copyWith(
        color: expired ? AppColors.error : AppColors.textSecondary,
      ),
    );
  }
}

class _InlineBadge extends StatelessWidget {
  const _InlineBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    // Flexible + ellipsis rather than a bare Text: on an extremely narrow
    // card (small phones, several badges at once) the available width can
    // shrink to just a few pixels — this truncates gracefully instead of
    // throwing a RenderFlex overflow.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: AppTypography.bodySmall
                .copyWith(color: AppColors.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
