import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/real_customer_check.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/screens/login_screen.dart';
import '../../domain/models/loyalty_account_snapshot.dart';
import '../providers/loyalty_providers.dart';
import '../widgets/abacus_card.dart';
import '../widgets/loyalty_history_tile.dart';
import '../widgets/loyalty_progress.dart';
import 'loyalty_history_screen.dart';
import 'rewards_screen.dart';

/// P3A (2026-08-23) — the canonical, real, server-authoritative Boncuklarım
/// screen. Replaces the entirely mock implementation previously at
/// `features/profile/presentation/screens/loyalty_screen.dart` (fake
/// balance, fake bronze/silver/gold tiers, mock rewards catalog, a
/// client-side `Random()` wheel, fake campaigns, fake history — none of
/// which is preserved here; see `docs/decisions.md`'s P3A entry for the
/// full audit). `lib/features/loyalty/` is now the canonical owner of the
/// real customer loyalty feature — Boncuk is no longer Profile-domain
/// business logic.
///
/// **No tiers, no wheel, no campaigns** — all remain unimplemented product
/// decisions (BR-LOYALTY-008/009, campaigns is a separate future customer
/// phase) and are deliberately absent rather than shown as fake/disabled
/// UI, per this phase's own locked scope. **The Reward Catalog ("Ödüller")
/// is real as of P7-B/P7-C/P7-C.1/P7-D (2026-08-24)** — see the
/// `_RewardsEntrySection` below, sourced from the server-authoritative
/// `getCustomerLoyaltyRewardCatalog`, never a mock.
///
/// Real, phone-verified customer only — a guest/unauthenticated session
/// sees [_GuestLoyaltyPrompt] instead of ever touching the loyalty
/// backend, mirroring `ProfileHeroCard`'s own guest/authenticated split.
///
/// **P3A Visual Polish (2026-08-24)**: the hero/progress/how-it-works/
/// movements sections below were redesigned for visual density and premium
/// styling after the first physical-device review — no data source, no
/// backend contract, and no business logic changed by that pass; only
/// composition, spacing, and copy tone did.
///
/// **Configurable Loyalty Economics (2026-08-24)**: every Boncuk rate/
/// redemption/max-redemption figure this screen renders comes from
/// [LoyaltyAccountSnapshot]'s real, server-resolved instance fields — never
/// a Flutter constant. See `functions/src/loyaltyPolicy.ts` and
/// `docs/decisions.md`.
class LoyaltyScreen extends ConsumerWidget {
  const LoyaltyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    return isRealCustomer(authState)
        ? const _AuthenticatedLoyaltyScreen()
        : const _GuestLoyaltyPrompt();
  }
}

class _AuthenticatedLoyaltyScreen extends ConsumerWidget {
  const _AuthenticatedLoyaltyScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(loyaltySnapshotProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Boncuklarım'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: snapshotAsync.when(
          loading: () => const _LoyaltyScreenSkeleton(),
          error: (error, stackTrace) => ErrorView(
            message: 'Boncuk bilgilerine şu anda ulaşılamıyor.',
            retryLabel: 'Tekrar Dene',
            onRetry: () => ref.invalidate(loyaltySnapshotProvider),
          ),
          data: (snapshot) => RefreshIndicator(
            onRefresh: () => Future.wait([
              ref.refresh(loyaltySnapshotProvider.future),
              ref.refresh(loyaltyHistoryProvider.future),
            ]),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AbacusCard(snapshot: snapshot),
                  const SizedBox(height: AppSpacing.md),
                  LoyaltyProgressCard(snapshot: snapshot),
                  const SizedBox(height: AppSpacing.md),
                  _HowItWorksCard(snapshot: snapshot),
                  const SizedBox(height: AppSpacing.md),
                  const _RewardsEntrySection(),
                  const SizedBox(height: AppSpacing.xl),
                  const _MovementsSection(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// P3A Visual Polish (2026-08-24) — replaces the previous plain text-list
/// card with 3 compact premium chips. **Configurable Loyalty Economics
/// (2026-08-24)**: every figure is read directly from [snapshot]'s real,
/// server-resolved policy fields — never a Flutter constant, never a
/// derived example multiplier. At the current default policy this renders
/// "50 TL → 5 Boncuk" because `earningSpendMinorUnits`/`earningBoncukAmount`
/// literally are 5000/5 — for a different organization's own configured
/// policy, this chip shows that organization's real numbers instead.
/// Formats a TL amount for display — a whole TL amount renders with no
/// decimals ("50 TL"); a genuinely fractional amount renders with exactly
/// two decimals ("0.50 TL"). Same-day correction (2026-08-24): every
/// economics figure is now a genuinely arbitrary server-configured value —
/// a fixed `toStringAsFixed(0)` would silently round a sub-1-TL redemption
/// value (e.g. `50` minor units = "0.50 TL") down to "0", or a non-round
/// spend threshold to the wrong whole number.
String _formatTl(double valueTl) {
  final isWhole = valueTl == valueTl.roundToDouble();
  return isWhole ? valueTl.toStringAsFixed(0) : valueTl.toStringAsFixed(2);
}

/// Formats a basis-points value as a percentage, with the same
/// whole-vs-fractional discipline as [_formatTl].
String _formatPercent(double percent) {
  final isWhole = percent == percent.roundToDouble();
  return isWhole ? percent.toStringAsFixed(0) : percent.toStringAsFixed(2);
}

class _HowItWorksCard extends StatelessWidget {
  const _HowItWorksCard({required this.snapshot});

  final LoyaltyAccountSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final earningSpendTl = _formatTl(snapshot.earningSpendMinorUnits / 100);
    final redemptionTl =
        _formatTl(snapshot.redemptionValueMinorUnitsPerBoncuk / 100);
    final maxRedemptionPercent =
        _formatPercent(snapshot.maxRedemptionBasisPoints / 100);

    return Column(
      key: const Key('loyaltyHowItWorksCard'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Nasıl Çalışır?',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // `IntrinsicHeight` (not `CrossAxisAlignment.stretch` alone) is
        // required here: this `Row` sits inside a `Column` with
        // `mainAxisSize.min` inside a `SingleChildScrollView`, so its own
        // height is unbounded — `stretch` on an unbounded-height `Row`
        // requests infinite height from its `Expanded` children and crashes
        // `performLayout()`. `IntrinsicHeight` measures the tallest chip
        // first, turning that into a real, finite height the `Row` can then
        // stretch every chip to match.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _HowItWorksChip(
                  icon: Icons.savings_rounded,
                  text:
                      '$earningSpendTl TL → ${snapshot.earningBoncukAmount} Boncuk',
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _HowItWorksChip(
                  icon: Icons.currency_lira_rounded,
                  text: '1 Boncuk → $redemptionTl TL',
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _HowItWorksChip(
                  icon: Icons.percent_rounded,
                  text: "En fazla %$maxRedemptionPercent'si",
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HowItWorksChip extends StatelessWidget {
  const _HowItWorksChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.md,
        horizontal: AppSpacing.xs,
      ),
      decoration: const BoxDecoration(
        color: AppColors.primaryExtraLight,
        borderRadius: AppRadius.kLarge,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(height: AppSpacing.xs),
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Boncuk Loyalty Program P7-D (2026-08-24) — "Boncuklarım → Ödüller" entry
/// point. A compact card, never the full catalog inline — tapping it
/// navigates to [RewardsScreen], the real server-authoritative listing.
class _RewardsEntrySection extends StatelessWidget {
  const _RewardsEntrySection();

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const Key('loyaltyRewardsEntryCard'),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const RewardsScreen()),
      ),
      borderRadius: AppRadius.kMedium,
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: const BoxDecoration(
                color: AppColors.primaryExtraLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.redeem_rounded, color: AppColors.primary),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ödüller', style: AppTypography.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    'Boncuklarınla gerçek ödülleri kullan',
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _MovementsSection extends ConsumerWidget {
  const _MovementsSection();

  static const _previewCount = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(loyaltyHistoryProvider);
    final hasEntriesToSeeAll =
        (historyAsync.valueOrNull?.entries.length ?? 0) > _previewCount ||
            (historyAsync.valueOrNull?.hasMore ?? false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Boncuk Hareketleri', style: AppTypography.titleLarge),
            if (hasEntriesToSeeAll)
              TextButton(
                key: const Key('loyaltySeeAllHistoryButton'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const LoyaltyHistoryScreen(),
                  ),
                ),
                child: const Text('Tümünü Gör'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        historyAsync.when(
          loading: () => const AppCard(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Center(
                child: CircularProgressIndicator(
                    color: AppColors.primary, strokeWidth: 2.4)),
          ),
          error: (error, stackTrace) => Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: ErrorView(
              message: 'Boncuk geçmişi şu anda yüklenemedi.',
              retryLabel: 'Tekrar Dene',
              onRetry: () => ref.invalidate(loyaltyHistoryProvider),
            ),
          ),
          data: (state) {
            if (state.entries.isEmpty) {
              return AppCard(
                key: const Key('loyaltyMovementsEmptyState'),
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.lg,
                  horizontal: AppSpacing.lg,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.history_rounded,
                      size: 20,
                      color: AppColors.textSecondary.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Henüz Boncuk hareketin yok.',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              );
            }
            final preview = state.entries.take(_previewCount).toList();
            return AppCard(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < preview.length; i++) ...[
                    LoyaltyHistoryTile(entry: preview[i]),
                    if (i != preview.length - 1)
                      const Divider(height: 1, color: AppColors.border),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _LoyaltyScreenSkeleton extends StatelessWidget {
  const _LoyaltyScreenSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget block({double height = 20, double? width}) => DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: AppRadius.kSmall,
          ),
          child: SizedBox(height: height, width: width),
        );

    return SingleChildScrollView(
      key: const Key('loyaltyScreenSkeleton'),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: AppRadius.kExtraLarge,
            ),
            child: SizedBox(height: 150),
          ),
          const SizedBox(height: AppSpacing.md),
          block(height: 96),
          const SizedBox(height: AppSpacing.md),
          block(height: 88),
          const SizedBox(height: AppSpacing.xl),
          block(height: 24, width: 160),
          const SizedBox(height: AppSpacing.md),
          block(height: 120),
        ],
      ),
    );
  }
}

/// Never touches the loyalty backend on a guest's behalf — mirrors
/// `ProfileHeroCard`'s own `_GuestHero` guest/authenticated split, applied
/// to a full screen since this is the pushed destination, not an embedded
/// card.
class _GuestLoyaltyPrompt extends StatelessWidget {
  const _GuestLoyaltyPrompt();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Boncuklarım'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              key: const Key('loyaltyGuestPrompt'),
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.eco_rounded,
                  size: 64,
                  color: AppColors.primary,
                ),
                const SizedBox(height: AppSpacing.lg),
                const Text(
                  'Boncuklarını görmek için giriş yap',
                  style: AppTypography.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Her uygun siparişinle Boncuk kazan, birikimini burada '
                  'takip et.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xl),
                ElevatedButton(
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const LoginScreen()),
                  ),
                  child: const Text('Giriş Yap'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
