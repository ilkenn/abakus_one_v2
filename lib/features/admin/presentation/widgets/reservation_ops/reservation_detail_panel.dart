import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../shared/widgets/feedback/error_view.dart';
import '../../../../../shared/widgets/feedback/loading_view.dart';
import '../../../../reservation/domain/models/reservation_status.dart';
import '../../../../reservation/domain/models/reservation_summary.dart';
import '../../../data/admin_reservation_gateway.dart';
import '../../../domain/reservations/admin_reservation_error_messages.dart';
import '../../../domain/reservations/admin_reservation_proposal_history_entry.dart';
import '../../../domain/reservations/admin_reservation_summary.dart';
import '../../providers/admin_reservation_dependencies_provider.dart';
import '../../providers/admin_reservation_detail_provider.dart';
import 'admin_reservation_status_copy.dart';
import 'reservation_propose_change_dialog.dart';
import 'reservation_table_assignment_section.dart';
import 'reservation_table_session_section.dart';

const List<String> _monthNames = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];

String _formatDateTime(DateTime dt) {
  final local = dt.toLocal();
  return '${local.day} ${_monthNames[local.month - 1]} ${local.year}, '
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

/// Faz R.3A §6 — the reservation detail panel: every field §6 lists
/// (customer name, verified-phone-at-submission is not stored on the
/// Reservation itself — the customer's contact NAME is; phone number
/// lives only on the Firebase Auth account, never duplicated onto the
/// Reservation document, so it is intentionally not shown here), status,
/// requested/confirmed time+area, party size, change-proposal history,
/// assigned table, preorder summary. Internal hold/bucket ids are never
/// fetched into any model this panel reads, so there is nothing to
/// accidentally render.
class ReservationDetailPanel extends ConsumerWidget {
  const ReservationDetailPanel(
      {super.key, required this.reservationId, this.onClose});

  final String reservationId;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync =
        ref.watch(adminReservationDetailProvider(reservationId));

    return Container(
      color: AppColors.background,
      child: detailAsync.when(
        loading: () => const LoadingView(message: 'Rezervasyon yükleniyor...'),
        error: (error, stackTrace) => const ErrorView(
            message: 'Rezervasyon yüklenirken bir sorun oluştu.'),
        data: (reservation) {
          if (reservation == null) {
            return const ErrorView(message: 'Rezervasyon bulunamadı.');
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (onClose != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: onClose),
                  ),
                _StatusHeader(reservation: reservation),
                const SizedBox(height: AppSpacing.lg),
                _CoreInfoCard(reservation: reservation),
                if (reservation.status == ReservationStatus.changeProposed) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _ActiveProposalCard(reservation: reservation),
                ],
                const SizedBox(height: AppSpacing.lg),
                _ConfirmRejectActions(reservation: reservation),
                const SizedBox(height: AppSpacing.lg),
                _TerminalActionsSection(reservation: reservation),
                if (reservation.status == ReservationStatus.confirmed) ...[
                  const SizedBox(height: AppSpacing.lg),
                  ReservationTableAssignmentSection(reservation: reservation),
                  if (reservation.hasAssignedTable) ...[
                    const SizedBox(height: AppSpacing.lg),
                    ReservationTableSessionSection(reservation: reservation),
                  ],
                ],
                if (reservation.hasPreorder) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _PreorderSummaryCard(orderId: reservation.preorderOrderId!),
                ],
                const SizedBox(height: AppSpacing.lg),
                _ProposalHistorySection(reservationId: reservationId),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.reservation});
  final AdminReservationSummary reservation;

  @override
  Widget build(BuildContext context) {
    final color = adminReservationStatusColor(reservation.status);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: AppRadius.kMedium),
      child: Row(
        children: [
          Icon(adminReservationStatusIcon(reservation.status), color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              adminReservationStatusLabel(reservation.status),
              style: AppTypography.titleMedium.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoreInfoCard extends ConsumerWidget {
  const _CoreInfoCard({required this.reservation});
  final AdminReservationSummary reservation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final areasAsync = ref.watch(adminReservationBranchAreasProvider);
    String areaLabel(String? areaId) {
      if (areaId == null) return '—';
      return areasAsync.maybeWhen(
        data: (areas) =>
            areas
                .where((a) => a.id == areaId)
                .map((a) => a.displayName)
                .firstOrNull ??
            areaId,
        orElse: () => areaId,
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.kMedium,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _InfoRow(
              icon: Icons.person_outline_rounded,
              label: 'Müşteri',
              value: reservation.contactFullName),
          _InfoRow(
              icon: Icons.people_alt_rounded,
              label: 'Kişi Sayısı',
              value: '${reservation.partySize}'),
          _InfoRow(
            icon: Icons.calendar_today_rounded,
            label: 'Talep Edilen',
            value:
                '${_formatDateTime(reservation.requestedTime)} · ${areaLabel(reservation.requestedAreaId)}',
          ),
          if (reservation.confirmedTime != null)
            _InfoRow(
              icon: Icons.event_available_rounded,
              label: 'Onaylanan',
              value:
                  '${_formatDateTime(reservation.confirmedTime!)} · ${areaLabel(reservation.confirmedAreaId)}',
            ),
          if (reservation.assignedTableId != null)
            _InfoRow(
                icon: Icons.table_bar_rounded,
                label: 'Masa',
                value: reservation.assignedTableId!),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 110,
            child: Text(label,
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary)),
          ),
          Expanded(
              child: Text(value,
                  style: AppTypography.bodyMedium
                      .copyWith(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

class _ActiveProposalCard extends StatelessWidget {
  const _ActiveProposalCard({required this.reservation});
  final AdminReservationSummary reservation;

  @override
  Widget build(BuildContext context) {
    final deadline = reservation.activeProposalCustomerResponseDeadlineAt;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: const BoxDecoration(
          color: AppColors.primaryExtraLight, borderRadius: AppRadius.kMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Müşteriye Önerilen', style: AppTypography.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          if (deadline != null)
            Text(
              'Yanıt son tarihi: ${_formatDateTime(deadline)}',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }
}

class _ConfirmRejectActions extends ConsumerStatefulWidget {
  const _ConfirmRejectActions({required this.reservation});
  final AdminReservationSummary reservation;

  @override
  ConsumerState<_ConfirmRejectActions> createState() =>
      _ConfirmRejectActionsState();
}

class _ConfirmRejectActionsState extends ConsumerState<_ConfirmRejectActions> {
  bool _isBusy = false;
  String? _error;

  Future<void> _confirm() async {
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      await ref
          .read(adminReservationGatewayProvider)
          .confirmReservation(reservationId: widget.reservation.id);
    } on AdminReservationException catch (error) {
      if (!mounted) return;
      setState(() => _error = adminReservationErrorMessage(error));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _reject() async {
    final result = await showDialog<({String reasonCode, String? reason})>(
      context: context,
      builder: (context) => const _RejectReasonDialog(),
    );
    if (result == null) return;
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      await ref.read(adminReservationGatewayProvider).rejectReservation(
            reservationId: widget.reservation.id,
            reasonCode: result.reasonCode,
            reason: result.reason,
          );
    } on AdminReservationException catch (error) {
      if (!mounted) return;
      setState(() => _error = adminReservationErrorMessage(error));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _proposeChange() async {
    await showDialog<void>(
      context: context,
      builder: (context) =>
          ReservationProposeChangeDialog(reservation: widget.reservation),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPending = widget.reservation.status ==
        ReservationStatus.pendingRestaurantApproval;
    if (!isPending) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: AppRadius.kMedium),
            child: Text(_error!,
                style:
                    AppTypography.bodySmall.copyWith(color: AppColors.error)),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _isBusy ? null : _reject,
                child: const Text('Rezervasyonu Reddet'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: ElevatedButton(
                onPressed: _isBusy ? null : _confirm,
                child: const Text('Onayla'),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: _isBusy ? null : _proposeChange,
          icon: const Icon(Icons.swap_horiz_rounded, size: 18),
          label: const Text('Alternatif Saat/Alan Öner'),
        ),
      ],
    );
  }
}

/// Faz R.3B §21 — staff terminal actions: cancel (from any non-terminal
/// status), complete/no-show (confirmed, once `confirmedTime` has passed).
/// Every action requires a destructive confirmation dialog; cancel/no-show
/// additionally warn before the final confirmation when the linked
/// preorder has already been released to the kitchen (§6/§13's own LOCKED
/// rule: staff may still proceed, but the preorder is never auto-cancelled
/// for them). Advisory only — the backend remains the final authority on
/// every actual attempt.
class _TerminalActionsSection extends ConsumerStatefulWidget {
  const _TerminalActionsSection({required this.reservation});
  final AdminReservationSummary reservation;

  @override
  ConsumerState<_TerminalActionsSection> createState() =>
      _TerminalActionsSectionState();
}

class _TerminalActionsSectionState
    extends ConsumerState<_TerminalActionsSection> {
  bool _isBusy = false;
  String? _error;
  bool _preorderReleased = false;

  Future<bool> _confirmDestructive({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      await action();
    } on AdminReservationException catch (error) {
      if (!mounted) return;
      setState(() => _error = adminReservationErrorMessage(error));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _cancel() async {
    final message = _preorderReleased
        ? 'Bu rezervasyonun ön siparişi mutfağa iletilmiş.\n'
            'Rezervasyonun iptal edilmesi ön siparişi otomatik iptal etmez.\n\n'
            'Bu rezervasyonu iptal etmek istediğinizden emin misiniz?'
        : 'Bu rezervasyonu iptal etmek istediğinizden emin misiniz?';
    final confirmed = await _confirmDestructive(
      title: 'Rezervasyonu İptal Et',
      message: message,
      confirmLabel: 'İptal Et',
    );
    if (!confirmed || !mounted) return;
    await _run(
      () => ref
          .read(adminReservationGatewayProvider)
          .cancelReservation(reservationId: widget.reservation.id),
    );
  }

  Future<void> _complete() async {
    final confirmed = await _confirmDestructive(
      title: 'Rezervasyonu Tamamla',
      message:
          'Bu rezervasyonu tamamlandı olarak işaretlemek istediğinizden emin misiniz?',
      confirmLabel: 'Tamamlandı',
    );
    if (!confirmed || !mounted) return;
    await _run(
      () => ref
          .read(adminReservationGatewayProvider)
          .completeReservation(reservationId: widget.reservation.id),
    );
  }

  Future<void> _noShow() async {
    final message = _preorderReleased
        ? 'Bu rezervasyonun ön siparişi mutfağa iletilmiş.\n'
            'Rezervasyonu gelmedi olarak işaretlemek ön siparişi otomatik iptal etmez.\n\n'
            'Bu rezervasyonu gelmedi olarak işaretlemek istediğinizden emin misiniz?'
        : 'Bu rezervasyonu gelmedi olarak işaretlemek istediğinizden emin misiniz?';
    final confirmed = await _confirmDestructive(
      title: 'Gelmedi Olarak İşaretle',
      message: message,
      confirmLabel: 'Gelmedi',
    );
    if (!confirmed || !mounted) return;
    await _run(
      () => ref
          .read(adminReservationGatewayProvider)
          .markReservationNoShow(reservationId: widget.reservation.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reservation = widget.reservation;
    final status = reservation.status;

    // Re-evaluated on every build (not read inside a callback — `ref.watch`
    // is only ever valid during build) and cached in a field so the
    // action callbacks below can consult the latest known value.
    if (reservation.hasPreorder) {
      final preorderAsync =
          ref.watch(adminPreorderOrderProvider(reservation.preorderOrderId!));
      _preorderReleased = preorderAsync.maybeWhen(
        data: (preorder) =>
            preorder != null &&
            preorder.status != ReservationPreorderStatus.pendingConfirmation &&
            preorder.status != ReservationPreorderStatus.cancelled,
        orElse: () => false,
      );
    } else {
      _preorderReleased = false;
    }

    final canCancel = status == ReservationStatus.pendingRestaurantApproval ||
        status == ReservationStatus.changeProposed ||
        status == ReservationStatus.confirmed;
    final canCompleteOrNoShow = status == ReservationStatus.confirmed &&
        reservation.confirmedTime != null &&
        DateTime.now().isAfter(reservation.confirmedTime!);

    if (!canCancel && !canCompleteOrNoShow) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: AppRadius.kMedium),
            child: Text(_error!,
                style:
                    AppTypography.bodySmall.copyWith(color: AppColors.error)),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (canCompleteOrNoShow) ...[
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isBusy ? null : _noShow,
                  icon: const Icon(Icons.person_off_rounded, size: 18),
                  label: const Text('Gelmedi'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isBusy ? null : _complete,
                  icon: const Icon(Icons.task_alt_rounded, size: 18),
                  label: const Text('Tamamlandı'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (canCancel)
          OutlinedButton(
            onPressed: _isBusy ? null : _cancel,
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Rezervasyonu İptal Et'),
          ),
      ],
    );
  }
}

class _RejectReasonDialog extends StatefulWidget {
  const _RejectReasonDialog();

  @override
  State<_RejectReasonDialog> createState() => _RejectReasonDialogState();
}

class _RejectReasonDialogState extends State<_RejectReasonDialog> {
  String _reasonCode = 'fullyBooked';
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rezervasyonu Reddet'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButton<String>(
            value: _reasonCode,
            isExpanded: true,
            items: const [
              DropdownMenuItem(
                  value: 'fullyBooked', child: Text('Kapasite dolu')),
              DropdownMenuItem(
                  value: 'closedForEvent',
                  child: Text('Özel etkinlik nedeniyle kapalı')),
              DropdownMenuItem(value: 'other', child: Text('Diğer')),
            ],
            onChanged: (value) =>
                setState(() => _reasonCode = value ?? 'fullyBooked'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _reasonController,
            decoration: const InputDecoration(labelText: 'Not (opsiyonel)'),
            maxLength: 200,
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç')),
        FilledButton(
          onPressed: () => Navigator.pop(context, (
            reasonCode: _reasonCode,
            reason: _reasonController.text.trim().isEmpty
                ? null
                : _reasonController.text.trim(),
          )),
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          child: const Text('Reddet'),
        ),
      ],
    );
  }
}

/// Faz R.3A §17 — the admin preorder view: products, quantities,
/// modifiers/bowl contents, total, kitchen timing. Deliberately its own
/// operational copy, never the customer-facing status text reused blindly
/// — "pending future release" reads as an exact kitchen-dispatch time
/// ("Mutfağa gönderim: HH:mm"), not the customer's softer "we'll let you
/// know" framing. No manual release button — explicitly out of this
/// phase's scope.
class _PreorderSummaryCard extends ConsumerWidget {
  const _PreorderSummaryCard({required this.orderId});
  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preorderAsync = ref.watch(adminPreorderOrderProvider(orderId));

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.kMedium,
        border: Border.all(color: AppColors.border),
      ),
      child: preorderAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, stackTrace) => Text(
          'Ön sipariş yüklenirken bir sorun oluştu.',
          style: AppTypography.bodySmall.copyWith(color: AppColors.error),
        ),
        data: (preorder) {
          if (preorder == null) {
            return Text(
              'Ön sipariş bulunamadı.',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.restaurant_rounded,
                      color: AppColors.primary, size: 20),
                  SizedBox(width: AppSpacing.sm),
                  Text('Ön Sipariş', style: AppTypography.titleMedium),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final line in preorder.lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          '${line.quantity}x ${line.productName}'
                          '${line.modifierNames.isNotEmpty ? ' (${line.modifierNames.join(', ')})' : ''}',
                          style: AppTypography.bodySmall,
                        ),
                      ),
                      Text(
                        '${(line.lineTotalMinorUnits / 100).toStringAsFixed(0)} TL',
                        style: AppTypography.bodySmall
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              const Divider(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Toplam', style: AppTypography.bodyMedium),
                  Text(
                    '${(preorder.grandTotalMinorUnits / 100).toStringAsFixed(0)} TL',
                    style: AppTypography.bodyMedium
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(_kitchenTimingCopy(preorder),
                  style: AppTypography.caption
                      .copyWith(color: AppColors.textSecondary)),
            ],
          );
        },
      ),
    );
  }

  String _kitchenTimingCopy(ReservationPreorderSummary preorder) {
    if (preorder.status == ReservationPreorderStatus.cancelled) {
      return 'Ön sipariş iptal';
    }
    if (preorder.status == ReservationPreorderStatus.confirmed) {
      return 'Mutfağa iletildi';
    }
    final releaseAt = preorder.kitchenReleaseAt;
    if (releaseAt != null) {
      final local = releaseAt.toLocal();
      return 'Mutfağa gönderim: ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    return 'Rezervasyon onaylandığında mutfağa gönderim zamanı burada görünecek.';
  }
}

class _ProposalHistorySection extends ConsumerWidget {
  const _ProposalHistorySection({required this.reservationId});
  final String reservationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync =
        ref.watch(adminReservationProposalHistoryProvider(reservationId));
    return historyAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stackTrace) => const SizedBox.shrink(),
      data: (entries) {
        if (entries.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Öneri Geçmişi', style: AppTypography.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            for (final entry in entries) _ProposalHistoryRow(entry: entry),
          ],
        );
      },
    );
  }
}

class _ProposalHistoryRow extends StatelessWidget {
  const _ProposalHistoryRow({required this.entry});
  final AdminReservationProposalHistoryEntry entry;

  String get _statusLabel {
    switch (entry.status) {
      case AdminProposalStatus.pendingCustomerResponse:
        return 'Yanıt bekleniyor';
      case AdminProposalStatus.accepted:
        return 'Kabul edildi';
      case AdminProposalStatus.rejected:
        return 'Reddedildi';
      case AdminProposalStatus.expired:
        return 'Süresi doldu';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.kMedium,
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_formatDateTime(entry.fromTime)} → ${_formatDateTime(entry.proposedTime)}',
              style: AppTypography.bodySmall,
            ),
            const SizedBox(height: 2),
            Text(_statusLabel,
                style: AppTypography.caption
                    .copyWith(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
