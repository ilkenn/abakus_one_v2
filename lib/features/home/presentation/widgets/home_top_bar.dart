import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/badges/boncuk_balance_pill.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../restaurant/presentation/providers/restaurant_status_provider.dart';

/// The restaurant name shown in the compact top bar. No `Branch`/branch-
/// selection provider exists anywhere in this codebase yet
/// (`shared/models/branch.dart` is defined but never instantiated) — this
/// is a deliberate static placeholder until one does, per product decision.
const String kStaticBranchName = 'Abaküs Ortaköy';

/// One compact row: branch name + open/closed status, Boncuk balance,
/// notification action. Deliberately not a card — per the Home redesign's
/// explicit "do not create another large branch info card" requirement,
/// this replaces the old multi-line bordered status block entirely. ETA and
/// delivery-zone/location data are dropped from Home altogether, not just
/// compacted.
class HomeTopBar extends ConsumerWidget {
  final VoidCallback onBoncukTap;
  final VoidCallback onNotificationsTap;

  const HomeTopBar({
    super.key,
    required this.onBoncukTap,
    required this.onNotificationsTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAuthenticated = ref.watch(
      authProvider.select((state) => state.isAuthenticated),
    );
    final isOpen = ref.watch(
      restaurantStatusProvider.select((s) => s.isOpen && s.acceptsOrders),
    );

    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  kStaticBranchName,
                  style: AppTypography.labelLarge.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isOpen ? AppColors.success : AppColors.error,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                isOpen ? 'Açık' : 'Kapalı',
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isOpen ? AppColors.success : AppColors.error,
                ),
              ),
            ],
          ),
        ),
        if (isAuthenticated) ...[
          GestureDetector(
            onTap: onBoncukTap,
            child: Semantics(
              button: true,
              label: 'Boncuk bakiyen, detay için dokun',
              child: const BoncukBalancePill(),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
        Semantics(
          button: true,
          label: 'Bildirimler',
          child: IconButton(
            icon: const Icon(
              Icons.notifications_outlined,
              color: AppColors.textPrimary,
            ),
            onPressed: onNotificationsTap,
          ),
        ),
      ],
    );
  }
}
