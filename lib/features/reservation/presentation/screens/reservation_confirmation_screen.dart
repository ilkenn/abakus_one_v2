import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../cart/presentation/screens/order_success_screen.dart';
import '../../domain/models/reservation_area.dart';
import '../../domain/models/reservation_status.dart';
import '../../domain/models/reservation_summary.dart';
import '../providers/reservation_branch_info_provider.dart';
import '../providers/reservation_dependencies_provider.dart';

const List<String> _confirmationMonthNames = [
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

/// Shown immediately after a successful `submitReservation` call — Faz
/// R.2 §15/§16. Never claims the reservation is confirmed
/// (`status == pendingRestaurantApproval` at this point, always) and never
/// shows internal ids/diagnostics (hold ids, occupancy, backend error
/// text) — only what the customer actually asked for.
class ReservationConfirmationScreen extends ConsumerWidget {
  const ReservationConfirmationScreen({super.key, required this.reservationId});

  final String reservationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(reservationRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rezervasyon Talebi'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: StreamBuilder<ReservationSummary?>(
          stream: repository.watchReservation(reservationId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const LoadingView(
                  message: 'Rezervasyon bilgileri yükleniyor...');
            }
            if (snapshot.hasError || snapshot.data == null) {
              return const ErrorView(
                message: 'Rezervasyon bilgileri şu anda görüntülenemiyor.',
              );
            }
            final reservation = snapshot.data!;
            return _ConfirmationBody(reservation: reservation);
          },
        ),
      ),
    );
  }
}

class _ConfirmationBody extends ConsumerWidget {
  const _ConfirmationBody({required this.reservation});

  final ReservationSummary reservation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFullSlot =
        reservation.status == ReservationStatus.pendingRestaurantApproval;
    final date = reservation.requestedTime.toLocal();
    final branchInfoAsync = ref.watch(reservationBranchInfoProvider);
    final areaDisplayName = branchInfoAsync.maybeWhen(
      data: (info) => info.areas
          .firstWhere(
            (a) => a.id == reservation.requestedAreaId,
            orElse: () => ReservationArea(
              id: reservation.requestedAreaId,
              displayName: reservation.requestedAreaId,
            ),
          )
          .displayName,
      orElse: () => reservation.requestedAreaId,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.mark_email_read_rounded,
              size: 56, color: AppColors.primary),
          const SizedBox(height: AppSpacing.lg),
          const Text(
            'Rezervasyon talebiniz restorana iletildi.',
            style: AppTypography.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Henüz onaylanmadı — restoran en kısa sürede size dönüş yapacak.',
            style: AppTypography.bodyMedium
                .copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          if (isFullSlot) ...[
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: const BoxDecoration(
                color: AppColors.primaryExtraLight,
                borderRadius: AppRadius.kMedium,
              ),
              child: Text(
                'Seçtiğiniz saat için müsaitlik sınırlı. Talebiniz restorana iletildi; '
                'restoran size alternatif bir saat önerebilir.',
                style:
                    AppTypography.bodySmall.copyWith(color: AppColors.primary),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadius.kMedium,
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                _SummaryRow(
                  icon: Icons.calendar_today_rounded,
                  label:
                      '${date.day} ${_confirmationMonthNames[date.month - 1]} ${date.year}, ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                ),
                _SummaryRow(
                  icon: Icons.deck_rounded,
                  label: areaDisplayName,
                ),
                _SummaryRow(
                  icon: Icons.people_alt_rounded,
                  label: '${reservation.partySize} kişi',
                ),
                if (reservation.preorder != null)
                  const _SummaryRow(
                    icon: Icons.restaurant_rounded,
                    label: 'Ön sipariş eklendi',
                  ),
              ],
            ),
          ),
          // Boncuk Loyalty Program P6-B (2026-08-24) — server-confirmed
          // only, and only when a real redemption happened (mirrors
          // `OrderSuccessScreen`'s own gate exactly, reusing the same
          // `BoncukSuccessSummary` widget verbatim — no second Boncuk
          // summary component). Every value here comes from the canonical
          // preorder order re-read via `ReservationRepository`, never a
          // pre-submit estimate.
          if (reservation.preorder?.hasBoncukSummary ?? false) ...[
            const SizedBox(height: AppSpacing.md),
            BoncukSuccessSummary(
              orderTotalMinorUnits: reservation.preorder!.grandTotalMinorUnits,
              boncukUsed: reservation.preorder!.boncukUsed!,
              boncukValueMinorUnits:
                  reservation.preorder!.boncukValueMinorUnits!,
              remainingPayableMinorUnits:
                  reservation.preorder!.remainingPayableMinorUnits!,
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          ElevatedButton(
            onPressed: () =>
                context.go(AppRoutes.reservationDetail(reservation.id)),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: const RoundedRectangleBorder(
                  borderRadius: AppRadius.kExtraLarge),
            ),
            child: const Text('Rezervasyonu Görüntüle'),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: () => context.go(AppRoutes.main),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: const RoundedRectangleBorder(
                  borderRadius: AppRadius.kExtraLarge),
            ),
            child: const Text('Ana Sayfaya Dön'),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
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
