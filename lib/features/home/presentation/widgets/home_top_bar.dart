import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../restaurant/presentation/providers/restaurant_status_provider.dart';

/// The restaurant name shown in the compact top bar. No `Branch`/branch-
/// selection provider exists anywhere in this codebase yet
/// (`shared/models/branch.dart` is defined but never instantiated) — this
/// is a deliberate static placeholder until one does, per product decision.
const String kStaticBranchName = 'Abaküs Ortaköy';

/// The premium Home header — H.1.1: a distinct compact card block (not a
/// bare row floating on the page background) carrying branch identity,
/// open/closed status (deliberately muted/secondary — a small tinted tag,
/// not a bold colored dot), a Boncuk entry action, and a circular
/// notification action. Still a single row's worth of content — "keep it
/// compact, do not turn it into a huge hero/giant AppBar" — the card
/// treatment itself (surface + border + soft shadow) is what gives it
/// "subtle separation from body," not extra height. ETA and delivery-zone/
/// location data stay dropped from Home altogether, not just compacted; no
/// separate location picker exists anywhere in this codebase to surface
/// here either — the branch name already carries the neighborhood
/// ("Abaküs Ortaköy").
///
/// H.1.1 loyalty mock-data correction, part 2: deliberately does **not**
/// use the shared `BoncukBalancePill` (`shared/widgets/badges/`) — that
/// widget reads `loyaltyProvider.currentBalance`, which is unconditionally
/// mock/seeded in every environment (see `boncuk_section.dart`'s own doc
/// comment for the full finding), so it would show a fake "320" on Home
/// exactly like the section below it used to. The pill itself is
/// deliberately left untouched — it's shared across 6+ other screens
/// (Menu/Cart/Checkout/Order Tracking/Loyalty/Product Detail), and fixing
/// it there is a separate, explicit decision this task didn't ask for.
/// Home's own header instead shows a neutral, non-numeric "Boncuklarım"
/// action — the loyalty entry point stays reachable, nothing about it is
/// fabricated.
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
    final statusColor = isOpen ? AppColors.success : AppColors.error;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.kLarge,
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.subtle,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.primaryExtraLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.eco_rounded,
              color: AppColors.primary,
              size: 18,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  kStaticBranchName,
                  style: AppTypography.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                // Deliberately secondary — a small muted tag, not a bold
                // colored dot+label, so it reads as supporting information
                // beneath the branch identity, not competing with it.
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: AppRadius.kPill,
                  ),
                  child: Text(
                    isOpen ? 'Açık' : 'Kapalı',
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isAuthenticated) ...[
            Semantics(
              button: true,
              label: 'Boncuklarım, detay için dokun',
              child: Material(
                color: AppColors.primaryExtraLight,
                borderRadius: AppRadius.kPill,
                child: InkWell(
                  onTap: onBoncukTap,
                  borderRadius: AppRadius.kPill,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.eco_rounded,
                          color: AppColors.primary,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Boncuklarım',
                          style: AppTypography.labelLarge.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          // Circular premium action, deliberately no numeric badge — no
          // real notification backend exists yet, so
          // `unreadNotificationsCountProvider` is honestly always `0`
          // (customer-side closure audit, 2026-08-26 — previously a
          // hardcoded mock value). A badge would have nothing real to show.
          Semantics(
            button: true,
            label: 'Bildirimler',
            child: Material(
              color: AppColors.surfaceVariant,
              shape: const CircleBorder(
                side: BorderSide(color: AppColors.border),
              ),
              child: InkWell(
                onTap: onNotificationsTap,
                customBorder: const CircleBorder(),
                child: const SizedBox(
                  width: 36,
                  height: 36,
                  child: Icon(
                    Icons.notifications_outlined,
                    color: AppColors.textPrimary,
                    size: 19,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
