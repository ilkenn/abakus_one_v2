import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../data/reservation_gateway.dart';
import '../../domain/reservation_error_messages.dart';
import '../providers/reservation_availability_provider.dart';

/// Step 4 — time slot. Faz R.2 §8: available/full are visually distinct,
/// but a full slot is never disabled — the backend's own R.1A rule ("full
/// slot request can still be created") is honored: tapping a full slot
/// selects it and shows the required soft-decline copy instead of
/// blocking the tap. No third "limited" tier is invented — the backend
/// only ever computes available/full.
class TimeStep extends ConsumerWidget {
  const TimeStep({
    super.key,
    required this.availabilityKey,
    required this.selectedTime,
    required this.onTimeSelected,
  });

  final ReservationAvailabilityKey availabilityKey;
  final DateTime? selectedTime;
  final ValueChanged<DateTime> onTimeSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final availabilityAsync =
        ref.watch(reservationAvailabilityProvider(availabilityKey));

    return availabilityAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
        child: LoadingView(message: 'Uygun saatler yükleniyor...'),
      ),
      error: (error, stackTrace) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
        child: ErrorView(
          message: error is ReservationException
              ? reservationErrorMessage(error)
              : 'Uygun saatler yüklenirken bir sorun oluştu.',
          retryLabel: 'Tekrar Dene',
          onRetry: () =>
              ref.invalidate(reservationAvailabilityProvider(availabilityKey)),
        ),
      ),
      data: (slots) {
        if (slots.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
            child: EmptyView(
              icon: Icons.event_busy_rounded,
              message:
                  'Seçtiğiniz tarihte müsait saat bulunmuyor. Lütfen başka bir tarih seçin.',
            ),
          );
        }

        final isFullSelected = selectedTime != null &&
            slots.any((s) => s.time == selectedTime && !s.available);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final slot in slots)
                  _TimeChip(
                    time: slot.time,
                    available: slot.available,
                    isSelected: selectedTime == slot.time,
                    onTap: () => onTimeSelected(slot.time),
                  ),
              ],
            ),
            if (isFullSelected) ...[
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: AppRadius.kMedium,
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        color: AppColors.textSecondary, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Bu saat için doğrudan müsaitlik görünmüyor. '
                        'Talebinizi yine de restorana iletebiliriz.',
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({
    required this.time,
    required this.available,
    required this.isSelected,
    required this.onTap,
  });

  final DateTime time;
  final bool available;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final local = time.toLocal();
    final label =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';

    final Color background;
    final Color foreground;
    final Color borderColor;
    if (isSelected) {
      background = AppColors.primary;
      foreground = AppColors.onPrimary;
      borderColor = AppColors.primary;
    } else if (available) {
      background = AppColors.surface;
      foreground = AppColors.textPrimary;
      borderColor = AppColors.border;
    } else {
      // Full — never disabled/unreachable, only visually distinct (never
      // color-alone: also carries a distinct icon, satisfying Faz R.2 §23).
      background = AppColors.surfaceVariant;
      foreground = AppColors.textSecondary;
      borderColor = AppColors.border;
    }

    return Semantics(
      button: true,
      selected: isSelected,
      label: available
          ? '$label, müsait'
          : '$label, müsaitlik sınırlı, yine de seçilebilir',
      child: Material(
        color: background,
        borderRadius: AppRadius.kPill,
        child: InkWell(
          borderRadius: AppRadius.kPill,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              borderRadius: AppRadius.kPill,
              border:
                  Border.all(color: borderColor, width: isSelected ? 1.5 : 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!available) ...[
                  Icon(Icons.error_outline_rounded,
                      size: 14, color: foreground),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: AppTypography.bodyMedium.copyWith(
                    color: foreground,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
