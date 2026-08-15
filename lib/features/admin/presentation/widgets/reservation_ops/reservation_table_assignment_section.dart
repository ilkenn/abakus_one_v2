import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../data/admin_reservation_gateway.dart';
import '../../../domain/reservations/admin_reservation_error_messages.dart';
import '../../../domain/reservations/admin_reservation_summary.dart';
import '../../providers/admin_reservation_dependencies_provider.dart';

/// Faz R.3A §10/§11 — physical table assignment and reassignment, both
/// through this one section (reassignment is the same
/// `assignReservationTable` callable, per its own documented shape — no
/// separate flow needed). Only tables the backend itself already scopes
/// to same-branch + confirmed-area + active (`listReservationTablesForArea`)
/// are ever shown; the backend remains the conflict authority — this UI
/// never invents its own availability logic, just reflects what it's
/// told.
class ReservationTableAssignmentSection extends ConsumerStatefulWidget {
  const ReservationTableAssignmentSection(
      {super.key, required this.reservation});

  final AdminReservationSummary reservation;

  @override
  ConsumerState<ReservationTableAssignmentSection> createState() =>
      _ReservationTableAssignmentSectionState();
}

class _ReservationTableAssignmentSectionState
    extends ConsumerState<ReservationTableAssignmentSection> {
  Future<List<ReservationTableOption>>? _future;
  bool _isAssigning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = ref
        .read(adminReservationGatewayProvider)
        .listTablesForArea(reservationId: widget.reservation.id);
  }

  Future<void> _assign(String tableId) async {
    setState(() {
      _isAssigning = true;
      _error = null;
    });
    try {
      await ref.read(adminReservationGatewayProvider).assignTable(
            reservationId: widget.reservation.id,
            tableId: tableId,
          );
      if (!mounted) return;
      setState(_load);
    } on AdminReservationException catch (error) {
      if (!mounted) return;
      setState(() => _error = adminReservationErrorMessage(error));
    } finally {
      if (mounted) setState(() => _isAssigning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasTable = widget.reservation.assignedTableId != null;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.kMedium,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(hasTable ? 'Masa Değiştir' : 'Masa Ata',
              style: AppTypography.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          if (_error != null) ...[
            Text(_error!,
                style:
                    AppTypography.bodySmall.copyWith(color: AppColors.error)),
            const SizedBox(height: AppSpacing.sm),
          ],
          FutureBuilder<List<ReservationTableOption>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                final error = snapshot.error;
                return Text(
                  error is AdminReservationException
                      ? adminReservationErrorMessage(error)
                      : 'Masalar yüklenirken bir sorun oluştu.',
                  style:
                      AppTypography.bodySmall.copyWith(color: AppColors.error),
                );
              }
              final tables = snapshot.data ?? const [];
              if (tables.isEmpty) {
                return Text(
                  'Bu alanda tanımlı masa bulunmuyor.',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                );
              }
              return Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final table in tables)
                    _TableChip(
                      table: table,
                      onTap: (_isAssigning || table.isCurrentlyAssigned)
                          ? null
                          : () => _assign(table.id),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TableChip extends StatelessWidget {
  const _TableChip({required this.table, required this.onTap});

  final ReservationTableOption table;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color background;
    final Color foreground;
    if (table.isCurrentlyAssigned) {
      background = AppColors.primary;
      foreground = AppColors.onPrimary;
    } else if (table.available) {
      background = AppColors.surface;
      foreground = AppColors.textPrimary;
    } else {
      background = AppColors.surfaceVariant;
      foreground = AppColors.textDisabled;
    }

    return Material(
      color: background,
      borderRadius: AppRadius.kPill,
      child: InkWell(
        onTap: table.available ? onTap : null,
        borderRadius: AppRadius.kPill,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: AppRadius.kPill,
            border: Border.all(
                color: table.isCurrentlyAssigned
                    ? AppColors.primary
                    : AppColors.border),
          ),
          child: Text(
            table.capacity != null
                ? '${table.displayName} (${table.capacity})'
                : table.displayName,
            style: AppTypography.bodyMedium.copyWith(color: foreground),
          ),
        ),
      ),
    );
  }
}
