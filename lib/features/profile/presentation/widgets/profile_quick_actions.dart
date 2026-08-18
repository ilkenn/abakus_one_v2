import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';

/// Three equal-weight quick-access cards directly under the profile hero
/// — P.1 (2026-08-19). Deliberately icon+label only: no counts, no
/// balance, no "3 sipariş" style badges — none of that data has a real
/// source yet (see `loyaltyProvider`'s documented mock seed), and showing
/// a number here would be exactly the fabricated-data risk this redesign
/// was asked to remove. Destinations are unchanged from the old settings
/// list — this only changes presentation/prominence, not navigation
/// targets or business logic.
class ProfileQuickActions extends StatelessWidget {
  final VoidCallback onBoncuklarim;
  final VoidCallback onSiparislerim;
  final VoidCallback onFavorilerim;

  const ProfileQuickActions({
    super.key,
    required this.onBoncuklarim,
    required this.onSiparislerim,
    required this.onFavorilerim,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('profileQuickActionsRow'),
      children: [
        Expanded(
          child: _QuickActionCard(
            key: const Key('quickAction_boncuklarim'),
            icon: Icons.stars_rounded,
            label: 'Boncuklarım',
            onTap: onBoncuklarim,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _QuickActionCard(
            key: const Key('quickAction_siparislerim'),
            icon: Icons.shopping_bag_outlined,
            label: 'Siparişlerim',
            onTap: onSiparislerim,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _QuickActionCard(
            key: const Key('quickAction_favorilerim'),
            icon: Icons.favorite_border_rounded,
            label: 'Favorilerim',
            onTap: onFavorilerim,
          ),
        ),
      ],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionCard({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: AppCard(
        borderRadius: AppRadius.kLarge,
        boxShadow: AppShadows.subtle,
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.kLarge,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.md,
              horizontal: AppSpacing.xs,
            ),
            child: ExcludeSemantics(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: AppColors.primary, size: 24),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    label,
                    style: AppTypography.labelLarge.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
