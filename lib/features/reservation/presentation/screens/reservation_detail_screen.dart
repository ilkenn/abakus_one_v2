import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../data/reservation_gateway.dart';
import '../../domain/models/reservation_area.dart';
import '../../domain/models/reservation_status.dart';
import '../../domain/models/reservation_summary.dart';
import '../../domain/reservation_error_messages.dart';
import '../providers/reservation_branch_info_provider.dart';
import '../providers/reservation_dependencies_provider.dart';

const List<String> _detailMonthNames = [
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

/// Faz R.2 §17 — the raw backend status enum is never shown to the
/// customer; every value maps to approved Turkish copy.
String _statusCopy(ReservationStatus status) {
  switch (status) {
    case ReservationStatus.pendingRestaurantApproval:
      return 'Restoran onayı bekleniyor';
    case ReservationStatus.changeProposed:
      return 'Restoran yeni bir seçenek önerdi';
    case ReservationStatus.confirmed:
      return 'Rezervasyonunuz onaylandı';
    case ReservationStatus.rejected:
      return 'Rezervasyon talebiniz onaylanmadı';
    case ReservationStatus.cancelled:
      return 'Rezervasyon iptal edildi';
    case ReservationStatus.completed:
      return 'Rezervasyon tamamlandı';
    // Faz R.3B §23 — customer-safe wording, never shaming/blaming the
    // customer for not showing up.
    case ReservationStatus.noShow:
      return 'Rezervasyon gerçekleşmedi';
  }
}

Color _statusColor(ReservationStatus status) {
  switch (status) {
    case ReservationStatus.pendingRestaurantApproval:
    case ReservationStatus.changeProposed:
      return AppColors.warning;
    case ReservationStatus.confirmed:
    case ReservationStatus.completed:
      return AppColors.success;
    case ReservationStatus.rejected:
    case ReservationStatus.cancelled:
      return AppColors.error;
    // Faz R.3B §23 — calm/neutral, never the same alarming red as an
    // outright rejection/cancellation.
    case ReservationStatus.noShow:
      return AppColors.textSecondary;
  }
}

IconData _statusIcon(ReservationStatus status) {
  switch (status) {
    case ReservationStatus.pendingRestaurantApproval:
      return Icons.hourglass_top_rounded;
    case ReservationStatus.changeProposed:
      return Icons.swap_horiz_rounded;
    case ReservationStatus.confirmed:
      return Icons.check_circle_rounded;
    case ReservationStatus.rejected:
      return Icons.cancel_rounded;
    case ReservationStatus.cancelled:
      return Icons.event_busy_rounded;
    case ReservationStatus.completed:
      return Icons.task_alt_rounded;
    case ReservationStatus.noShow:
      return Icons.person_off_rounded;
  }
}

/// Faz R.2 §17 — minimum customer reservation detail: status (never a raw
/// enum), requested/confirmed time+area, party size, and — when present —
/// the change-proposal and preorder UX (§18/§20).
class ReservationDetailScreen extends ConsumerWidget {
  const ReservationDetailScreen({super.key, required this.reservationId});

  final String reservationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(reservationRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Rezervasyon')),
      body: SafeArea(
        child: StreamBuilder<ReservationSummary?>(
          stream: repository.watchReservation(reservationId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const LoadingView(message: 'Rezervasyon yükleniyor...');
            }
            if (snapshot.hasError || snapshot.data == null) {
              return const ErrorView(message: 'Rezervasyon bulunamadı.');
            }
            return _DetailBody(reservation: snapshot.data!);
          },
        ),
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.reservation});

  final ReservationSummary reservation;

  String _areaName(WidgetRef ref, String areaId) {
    final branchInfoAsync = ref.watch(reservationBranchInfoProvider);
    return branchInfoAsync.maybeWhen(
      data: (info) => info.areas
          .firstWhere(
            (a) => a.id == areaId,
            orElse: () => ReservationArea(id: areaId, displayName: areaId),
          )
          .displayName,
      orElse: () => areaId,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date =
        (reservation.confirmedTime ?? reservation.requestedTime).toLocal();
    final areaId = reservation.confirmedAreaId ?? reservation.requestedAreaId;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: _statusColor(reservation.status).withValues(alpha: 0.08),
              borderRadius: AppRadius.kMedium,
            ),
            child: Row(
              children: [
                Icon(_statusIcon(reservation.status),
                    color: _statusColor(reservation.status)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _statusCopy(reservation.status),
                    style: AppTypography.titleMedium.copyWith(
                      color: _statusColor(reservation.status),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadius.kMedium,
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                _DetailRow(
                  icon: Icons.calendar_today_rounded,
                  label:
                      '${date.day} ${_detailMonthNames[date.month - 1]} ${date.year}, ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                ),
                _DetailRow(
                    icon: Icons.deck_rounded, label: _areaName(ref, areaId)),
                _DetailRow(
                    icon: Icons.people_alt_rounded,
                    label: '${reservation.partySize} kişi'),
              ],
            ),
          ),
          if (reservation.status == ReservationStatus.changeProposed &&
              reservation.activeProposal != null) ...[
            const SizedBox(height: AppSpacing.xl),
            _ChangeProposalCard(reservation: reservation),
          ],
          if (reservation.preorder != null) ...[
            const SizedBox(height: AppSpacing.xl),
            _PreorderStatusCard(
              reservation: reservation,
              preorder: reservation.preorder!,
            ),
          ],
          // Faz R.3B §20 — shown whenever server/business state could
          // plausibly make self-cancellation valid (any non-terminal
          // status); the backend remains the final authority on every
          // actual attempt (cutoff, released-preorder lock, ownership).
          if (!reservation.status.isTerminal) ...[
            const SizedBox(height: AppSpacing.xl),
            _CancelReservationSection(reservation: reservation),
          ],
        ],
      ),
    );
  }
}

/// Faz R.3B §20 — customer self-cancellation. Advisory only: this widget
/// never predicts the cutoff or preorder-release lock itself (both are
/// server-authoritative, computed against server time/state, not the
/// client's clock) — a rejection surfaces via [reservationErrorMessage],
/// which already carries the exact required "contact restorant" copy for
/// both LOCKED scenarios (§5/§6).
class _CancelReservationSection extends ConsumerStatefulWidget {
  const _CancelReservationSection({required this.reservation});

  final ReservationSummary reservation;

  @override
  ConsumerState<_CancelReservationSection> createState() =>
      _CancelReservationSectionState();
}

class _CancelReservationSectionState
    extends ConsumerState<_CancelReservationSection> {
  bool _isCancelling = false;
  String? _error;

  Future<void> _confirmAndCancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rezervasyonu İptal Et'),
        content: const Text(
            'Bu rezervasyonu iptal etmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Rezervasyonu İptal Et'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _isCancelling = true;
      _error = null;
    });
    try {
      await ref.read(reservationGatewayProvider).cancelReservation(
            reservationId: widget.reservation.id,
          );
    } on ReservationException catch (error) {
      if (!mounted) return;
      setState(() {
        _isCancelling = false;
        _error = reservationErrorMessage(error);
      });
      return;
    }
    if (!mounted) return;
    setState(() => _isCancelling = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          Text(_error!,
              style: AppTypography.bodySmall.copyWith(color: AppColors.error)),
          const SizedBox(height: AppSpacing.sm),
        ],
        OutlinedButton(
          onPressed: _isCancelling ? null : _confirmAndCancel,
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
          child: const Text('Rezervasyonu İptal Et'),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Text(label, style: AppTypography.bodyMedium),
        ],
      ),
    );
  }
}

/// Faz R.2 §18 — before/after proposal UX. Accept -> confirmed; reject ->
/// pendingRestaurantApproval, explicitly not terminal ("Restoran yeni bir
/// alternatif önerebilir."). Faz R.2 §19 — an expired proposal cannot be
/// accepted; the CTA row is removed once `isExpired`, replaced with a
/// neutral expiry notice.
class _ChangeProposalCard extends ConsumerStatefulWidget {
  const _ChangeProposalCard({required this.reservation});

  final ReservationSummary reservation;

  @override
  ConsumerState<_ChangeProposalCard> createState() =>
      _ChangeProposalCardState();
}

class _ChangeProposalCardState extends ConsumerState<_ChangeProposalCard> {
  bool _isResponding = false;
  String? _error;

  Future<void> _respond(bool accept) async {
    if (_isResponding) return;
    setState(() {
      _isResponding = true;
      _error = null;
    });
    try {
      await ref.read(reservationGatewayProvider).respondToProposedChange(
            reservationId: widget.reservation.id,
            proposalId: widget.reservation.activeProposalId!,
            accept: accept,
          );
    } on ReservationException catch (error) {
      if (!mounted) return;
      setState(() {
        _isResponding = false;
        _error = reservationErrorMessage(error);
      });
      return;
    }
    if (!mounted) return;
    setState(() => _isResponding = false);
  }

  @override
  Widget build(BuildContext context) {
    final proposal = widget.reservation.activeProposal!;
    final from = widget.reservation.requestedTime.toLocal();
    final to = proposal.proposedTime.toLocal();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: const BoxDecoration(
        color: AppColors.primaryExtraLight,
        borderRadius: AppRadius.kMedium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Restoran Önerisi', style: AppTypography.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Talep: ${from.day} ${_detailMonthNames[from.month - 1]}, '
            '${from.hour.toString().padLeft(2, '0')}:${from.minute.toString().padLeft(2, '0')}',
            style: AppTypography.bodyMedium
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            'Restoran önerisi: ${to.day} ${_detailMonthNames[to.month - 1]}, '
            '${to.hour.toString().padLeft(2, '0')}:${to.minute.toString().padLeft(2, '0')}',
            style:
                AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.md),
          if (proposal.isExpired) ...[
            Text(
              'Bu öneri için yanıt süresi doldu.',
              style: AppTypography.bodySmall.copyWith(color: AppColors.error),
            ),
          ] else ...[
            if (_error != null) ...[
              Text(_error!,
                  style:
                      AppTypography.bodySmall.copyWith(color: AppColors.error)),
              const SizedBox(height: AppSpacing.sm),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isResponding ? null : () => _respond(false),
                    child: const Text('Bu Öneriyi Reddet'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isResponding ? null : () => _respond(true),
                    child: const Text('Öneriyi Kabul Et'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Reddederseniz rezervasyonunuz iptal olmaz — restoran yeni bir alternatif önerebilir.',
              style: AppTypography.caption
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Faz R.2 §20 — never shows the raw `Order.status`. A future-releasing
/// preorder ("pendingConfirmation", `kitchenReleaseAt` in the future) gets
/// the "will be sent to the kitchen at HH:mm" copy — never "ön siparişiniz
/// onay bekliyor" (that would incorrectly suggest the *preorder itself*,
/// not the reservation, needs approval). An already-confirmed/immediately-
/// released preorder gets the "sent to the kitchen" copy.
class _PreorderStatusCard extends StatelessWidget {
  const _PreorderStatusCard(
      {required this.reservation, required this.preorder});

  final ReservationSummary reservation;
  final ReservationPreorderSummary preorder;

  @override
  Widget build(BuildContext context) {
    String copy;
    if (preorder.status == ReservationPreorderStatus.cancelled) {
      copy = 'Ön siparişiniz iptal edildi.';
    } else if (preorder.status == ReservationPreorderStatus.confirmed) {
      copy = 'Ön siparişiniz mutfağa iletildi.';
    } else if (preorder.kitchenReleaseAt != null) {
      final release = preorder.kitchenReleaseAt!.toLocal();
      copy =
          'Ön siparişiniz mutfağa ${release.hour.toString().padLeft(2, '0')}:${release.minute.toString().padLeft(2, '0')}\'da iletilecek.';
    } else {
      // Reservation not yet confirmed at all -- nothing scheduled yet.
      copy = 'Rezervasyonunuz onaylandığında ön siparişinizin mutfağa ne zaman '
          'iletileceğini burada görebilirsiniz.';
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.kMedium,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.restaurant_rounded,
              color: AppColors.primary, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Ön Sipariş', style: AppTypography.titleMedium),
                const SizedBox(height: 4),
                Text(copy, style: AppTypography.bodyMedium),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '${preorder.grandTotalMinorUnits ~/ 100} TL',
                  style: AppTypography.priceMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
