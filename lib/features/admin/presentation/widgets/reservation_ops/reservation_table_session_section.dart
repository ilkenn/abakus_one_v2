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

/// Faz R.3A §12/§13 — "Rezervasyon Masasını Aç"/"Kapat", both real,
/// server-authoritative calls. §12's exact two-step handshake: the first
/// `openTable` call never carries the acknowledge flag; on the specific
/// soft "active walk-in session" conflict, a confirmation dialog offers
/// [Vazgeç]/[Yine de Aç] — only the second call sets
/// `acknowledgeActiveSessionConflict: true`, never client-side-bypassed.
/// §13's copy is explicit about what closing does *not* do (never
/// completes the Reservation, never kills customer sessions, never
/// restores protection) — this UI never implies otherwise.
class ReservationTableSessionSection extends ConsumerStatefulWidget {
  const ReservationTableSessionSection({super.key, required this.reservation});

  final AdminReservationSummary reservation;

  @override
  ConsumerState<ReservationTableSessionSection> createState() =>
      _ReservationTableSessionSectionState();
}

class _ReservationTableSessionSectionState
    extends ConsumerState<ReservationTableSessionSection> {
  bool _isBusy = false;
  String? _error;
  bool? _isOpen;

  Future<void> _open({bool acknowledge = false}) async {
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      final result = await ref.read(adminReservationGatewayProvider).openTable(
            reservationId: widget.reservation.id,
            acknowledgeActiveSessionConflict: acknowledge,
          );
      if (!mounted) return;
      setState(() => _isOpen = result.opened);
    } on ActiveSessionConflictException {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Aktif Masa Oturumu Var'),
          content: const Text(
            'Bu masada halen aktif bir masa oturumu bulunuyor. '
            'Rezervasyon masasını yine de açmak istiyor musunuz?',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Vazgeç')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Yine de Aç')),
          ],
        ),
      );
      if (confirmed == true) {
        await _open(acknowledge: true);
        return;
      }
    } on AdminReservationException catch (error) {
      if (!mounted) return;
      setState(() => _error = adminReservationErrorMessage(error));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _close() async {
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      await ref
          .read(adminReservationGatewayProvider)
          .closeTable(reservationId: widget.reservation.id);
      if (!mounted) return;
      setState(() => _isOpen = false);
    } on AdminReservationException catch (error) {
      if (!mounted) return;
      setState(() => _error = adminReservationErrorMessage(error));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOpen = _isOpen ?? false;
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
          const Text('Rezervasyon Masası', style: AppTypography.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Masayı açmak gerçek dine-in kullanımını başlatır. Kapatmak '
            'rezervasyonu tamamlamaz, müşteri oturumlarını sonlandırmaz ve '
            'QR korumasını geri yüklemez.',
            style:
                AppTypography.caption.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
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
                  onPressed: (_isBusy || !isOpen) ? null : _close,
                  child: const Text('Rezervasyon Masasını Kapat'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: ElevatedButton(
                  onPressed: (_isBusy || isOpen) ? null : () => _open(),
                  child: const Text('Rezervasyon Masasını Aç'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
