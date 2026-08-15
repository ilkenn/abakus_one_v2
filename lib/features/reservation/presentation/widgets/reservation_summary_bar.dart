import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../providers/reservation_draft_provider.dart';

const List<String> _summaryMonthNames = [
  'Oca',
  'Şub',
  'Mar',
  'Nis',
  'May',
  'Haz',
  'Tem',
  'Ağu',
  'Eyl',
  'Eki',
  'Kas',
  'Ara',
];

/// The persistent "what you've chosen so far" strip — Faz R.2 §4: "Kullanıcı
/// her aşamada seçimlerini üstte/özet kartında görebilsin." Shows only the
/// selections already made; an unmade one is simply omitted, never a
/// placeholder dash.
class ReservationSummaryBar extends ConsumerWidget {
  const ReservationSummaryBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(reservationDraftProvider);
    final chips = <Widget>[
      if (draft.partySize != null)
        _SummaryChip(
            icon: Icons.people_alt_rounded, label: '${draft.partySize} kişi'),
      if (draft.area != null)
        _SummaryChip(icon: Icons.deck_rounded, label: draft.area!.displayName),
      if (draft.date != null)
        _SummaryChip(
          icon: Icons.calendar_today_rounded,
          label:
              '${draft.date!.day} ${_summaryMonthNames[draft.date!.month - 1]}',
        ),
      if (draft.time != null)
        _SummaryChip(
          icon: Icons.schedule_rounded,
          label:
              '${draft.time!.toLocal().hour.toString().padLeft(2, '0')}:${draft.time!.toLocal().minute.toString().padLeft(2, '0')}',
        ),
    ];

    if (chips.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      color: AppColors.primaryExtraLight,
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: chips,
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.kPill,
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.primary),
            const SizedBox(width: 4),
            Text(label,
                style: AppTypography.labelMedium
                    .copyWith(color: AppColors.primary)),
          ],
        ),
      ),
    );
  }
}
