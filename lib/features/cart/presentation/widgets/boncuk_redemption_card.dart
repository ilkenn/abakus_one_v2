import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../loyalty/domain/models/loyalty_account_snapshot.dart';

/// Formats a TL amount for display — a whole TL amount renders with no
/// decimals ("50 TL"); a genuinely fractional amount renders with exactly
/// two decimals ("0.50 TL"). Duplicated deliberately, not extracted to a
/// shared util — mirrors `AbacusCard`'s/`LoyaltyScreen`'s own established
/// per-file convention for this exact formatter.
String _formatTl(double valueTl) {
  final isWhole = valueTl == valueTl.roundToDouble();
  return isWhole ? valueTl.toStringAsFixed(0) : valueTl.toStringAsFixed(2);
}

/// Boncuk Loyalty Program P4-E-B (2026-08-22), reused unchanged for delivery
/// checkout P5-B (2026-08-24) — the premium "Boncuklarını Kullan" checkout
/// card, shared verbatim by `TakeawayCheckoutScreen` and
/// `DeliveryCheckoutScreen`. A presentational (dumb) widget: every economics
/// figure it renders is passed in by the caller's own [snapshotAsync]/
/// [maxUsableBoncuk], never computed or hardcoded here — this widget owns no
/// state, makes no server call, and has no channel-specific logic at all.
///
/// **Non-authoritative, by construction.** [maxUsableBoncuk] is a
/// presentation-only estimate the caller derives from the latest sanitized
/// [snapshotAsync] snapshot and the current (also approximate) cart total —
/// this card never claims it is the final word; the server (`submitTakeawayOrder`/
/// `submitDeliveryOrder`) revalidates everything independently. See
/// `TakeawayCheckoutScreen`'s own doc comment for the full estimate formula
/// and invalidation rules — `DeliveryCheckoutScreen` reuses the same
/// `computeClientEstimatedMaxBoncuk` function verbatim.
class BoncukRedemptionCard extends ConsumerWidget {
  const BoncukRedemptionCard({
    super.key,
    required this.snapshotAsync,
    required this.enabled,
    required this.selectedAmount,
    required this.maxUsableBoncuk,
    required this.selectionInvalid,
    required this.controlsFrozen,
    required this.cartTotalPriceTl,
    required this.onToggle,
    required this.onAmountChanged,
    required this.onUseMax,
    required this.onRetry,
  });

  final AsyncValue<LoyaltyAccountSnapshot> snapshotAsync;

  /// The customer's own explicit choice to use Boncuk at all — never
  /// silently flipped by a cart/snapshot change (see
  /// `TakeawayCheckoutScreen`'s own invalidation handling for the one
  /// exception: the estimated max genuinely reaching zero).
  final bool enabled;

  /// The customer's own explicit whole-Boncuk selection — never silently
  /// substituted with a different nonzero amount by this widget or its
  /// caller.
  final int selectedAmount;

  /// The current, non-authoritative estimated maximum usable Boncuk for
  /// this order, recomputed by the caller whenever the cart total or the
  /// loyalty snapshot changes.
  final int maxUsableBoncuk;

  /// `true` when [selectedAmount] no longer fits within [maxUsableBoncuk]
  /// (a cart/snapshot change happened after the customer chose it) — the
  /// caller must disable submission while this is `true`; this widget only
  /// renders the resulting notice and the explicit recovery actions
  /// (stepper/MAX/turn off), it never resolves the invalidity itself.
  final bool selectionInvalid;

  /// `true` while an order submission is in flight — freezes every control
  /// on this card (toggle/stepper/MAX), mirroring the existing
  /// `_isSubmitting`-frozen submit button.
  final bool controlsFrozen;

  /// The same approximate cart total (already labeled "tahminidir"
  /// elsewhere on this screen) [computeClientEstimatedMaxBoncuk] uses —
  /// reused here, presentation-only, to estimate the remaining payable
  /// amount. Never sent to the backend; never authoritative.
  final double cartTotalPriceTl;

  final ValueChanged<bool> onToggle;
  final ValueChanged<int> onAmountChanged;
  final VoidCallback onUseMax;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      key: const Key('boncukRedemptionCard'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Boncuklarını Kullan',
            style: AppTypography.titleMedium.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          snapshotAsync.when(
            loading: () => const _BoncukCardSkeleton(),
            error: (error, stackTrace) => _BoncukCardError(onRetry: onRetry),
            data: (snapshot) => _BoncukCardContent(
              snapshot: snapshot,
              enabled: enabled,
              selectedAmount: selectedAmount,
              maxUsableBoncuk: maxUsableBoncuk,
              selectionInvalid: selectionInvalid,
              controlsFrozen: controlsFrozen,
              cartTotalPriceTl: cartTotalPriceTl,
              onToggle: onToggle,
              onAmountChanged: onAmountChanged,
              onUseMax: onUseMax,
            ),
          ),
        ],
      ),
    );
  }
}

class _BoncukCardSkeleton extends StatelessWidget {
  const _BoncukCardSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget block({double height = 20, double? width}) => DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: AppRadius.kSmall,
          ),
          child: SizedBox(height: height, width: width),
        );

    return Column(
      key: const Key('boncukCardSkeleton'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        block(height: 18, width: 160),
        const SizedBox(height: AppSpacing.sm),
        block(height: 44),
      ],
    );
  }
}

class _BoncukCardError extends StatelessWidget {
  const _BoncukCardError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('boncukCardError'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ErrorView(
          message: 'Boncuk bilgilerine şu anda ulaşılamıyor.',
          retryLabel: 'Tekrar Dene',
          onRetry: onRetry,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Boncuk kullanmadan siparişini vermeye devam edebilirsin.',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _BoncukCardContent extends StatelessWidget {
  const _BoncukCardContent({
    required this.snapshot,
    required this.enabled,
    required this.selectedAmount,
    required this.maxUsableBoncuk,
    required this.selectionInvalid,
    required this.controlsFrozen,
    required this.cartTotalPriceTl,
    required this.onToggle,
    required this.onAmountChanged,
    required this.onUseMax,
  });

  final LoyaltyAccountSnapshot snapshot;
  final bool enabled;
  final int selectedAmount;
  final int maxUsableBoncuk;
  final bool selectionInvalid;
  final bool controlsFrozen;
  final double cartTotalPriceTl;
  final ValueChanged<bool> onToggle;
  final ValueChanged<int> onAmountChanged;
  final VoidCallback onUseMax;

  @override
  Widget build(BuildContext context) {
    // Canonical invariant (BR-LOYALTY-014): boncukDebt > 0 implies
    // spendableBalance == 0 — debt is checked first, never alongside a
    // "you have N Boncuk" line for the same account.
    if (snapshot.boncukDebt > 0) {
      return const _BoncukDebtState();
    }
    if (snapshot.spendableBalance <= 0) {
      return const _BoncukZeroState();
    }

    final redemptionValueTl = snapshot.redemptionValueMinorUnitsPerBoncuk / 100;
    final availableValueTl = snapshot.spendableBalance * redemptionValueTl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label:
              'Kullanılabilir Boncuk: ${snapshot.spendableBalance}, yaklaşık '
              '${_formatTl(availableValueTl)} TL değerinde',
          excludeSemantics: true,
          child: Row(
            children: [
              const Icon(Icons.eco_rounded, size: 18, color: AppColors.primary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Kullanılabilir: ${snapshot.spendableBalance} Boncuk '
                  '(≈ ${_formatTl(availableValueTl)} TL)',
                  style: AppTypography.bodyMedium,
                ),
              ),
              Semantics(
                label: enabled
                    ? 'Boncuk kullanımı açık'
                    : 'Boncuk kullanımı kapalı',
                excludeSemantics: true,
                child: Switch.adaptive(
                  key: const Key('boncukToggle'),
                  value: enabled,
                  activeThumbColor: AppColors.primary,
                  onChanged: (controlsFrozen || maxUsableBoncuk <= 0)
                      ? null
                      : onToggle,
                ),
              ),
            ],
          ),
        ),
        if (maxUsableBoncuk <= 0) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            key: const Key('boncukUnavailableForCartNotice'),
            'Bu sepet tutarıyla Boncuk kullanılamıyor.',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
        if (enabled && maxUsableBoncuk > 0) ...[
          const SizedBox(height: AppSpacing.md),
          _BoncukStepperRow(
            selectedAmount: selectedAmount,
            maxUsableBoncuk: maxUsableBoncuk,
            controlsFrozen: controlsFrozen,
            onAmountChanged: onAmountChanged,
            onUseMax: onUseMax,
          ),
          const SizedBox(height: AppSpacing.sm),
          _BoncukEstimateSummary(
            snapshot: snapshot,
            selectedAmount: selectedAmount,
            cartTotalPriceTl: cartTotalPriceTl,
          ),
          if (selectionInvalid) ...[
            const SizedBox(height: AppSpacing.sm),
            _BoncukInvalidSelectionNotice(onUseMax: onUseMax),
          ],
        ],
      ],
    );
  }
}

class _BoncukStepperRow extends StatelessWidget {
  const _BoncukStepperRow({
    required this.selectedAmount,
    required this.maxUsableBoncuk,
    required this.controlsFrozen,
    required this.onAmountChanged,
    required this.onUseMax,
  });

  final int selectedAmount;
  final int maxUsableBoncuk;
  final bool controlsFrozen;
  final ValueChanged<int> onAmountChanged;
  final VoidCallback onUseMax;

  @override
  Widget build(BuildContext context) {
    // Whole integers only (P4-E-B §6) — minimum 1 once enabled; the
    // decrement button disables at 1 rather than allowing 0 (turning
    // Boncuk fully off is the toggle's job, not the stepper's).
    final canDecrement = !controlsFrozen && selectedAmount > 1;
    final canIncrement = !controlsFrozen && selectedAmount < maxUsableBoncuk;
    final isAtMax = selectedAmount >= maxUsableBoncuk;

    return Row(
      children: [
        Semantics(
          label: 'Boncuk azalt',
          button: true,
          child: IconButton(
            key: const Key('boncukStepperDecrement'),
            onPressed:
                canDecrement ? () => onAmountChanged(selectedAmount - 1) : null,
            icon: const Icon(Icons.remove_circle_outline_rounded),
            color: AppColors.primary,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
        ),
        Expanded(
          child: Center(
            child: Semantics(
              label: 'Kullanılacak Boncuk: $selectedAmount',
              excludeSemantics: true,
              child: Text(
                key: const Key('boncukSelectedAmount'),
                '$selectedAmount Boncuk',
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ),
        Semantics(
          label: 'Boncuk artır',
          button: true,
          child: IconButton(
            key: const Key('boncukStepperIncrement'),
            onPressed:
                canIncrement ? () => onAmountChanged(selectedAmount + 1) : null,
            icon: const Icon(Icons.add_circle_outline_rounded),
            color: AppColors.primary,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Semantics(
          label: 'Maksimum Boncuk kullan: $maxUsableBoncuk',
          button: true,
          child: OutlinedButton(
            key: const Key('boncukMaxButton'),
            onPressed: (controlsFrozen || isAtMax) ? null : onUseMax,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            ),
            child: const Text('Maks. Kullan'),
          ),
        ),
      ],
    );
  }
}

class _BoncukEstimateSummary extends StatelessWidget {
  const _BoncukEstimateSummary({
    required this.snapshot,
    required this.selectedAmount,
    required this.cartTotalPriceTl,
  });

  final LoyaltyAccountSnapshot snapshot;
  final int selectedAmount;
  final double cartTotalPriceTl;

  @override
  Widget build(BuildContext context) {
    // Integer minor-unit arithmetic throughout — never floating point for
    // either multiplication (P4-E-B §8). The cart total is converted to
    // minor units exactly once, the same conversion
    // `computeClientEstimatedMaxBoncuk` already applies to this same
    // approximate value — everything after that is integer arithmetic.
    final estimatedValueMinorUnits =
        selectedAmount * snapshot.redemptionValueMinorUnitsPerBoncuk;
    final estimatedValueTl = estimatedValueMinorUnits / 100;

    final estimatedGrandTotalMinorUnits = (cartTotalPriceTl * 100).round();
    // Presentation-only, never authoritative, never sent to the backend —
    // clamped at 0 defensively (never shown negative) for the brief window
    // a selection can be larger than the current estimate, before the
    // caller's own invalidation notice/disabled-submit state resolves it.
    final estimatedRemainingMinorUnits =
        (estimatedGrandTotalMinorUnits - estimatedValueMinorUnits)
            .clamp(0, estimatedGrandTotalMinorUnits);
    final estimatedRemainingTl = estimatedRemainingMinorUnits / 100;

    return Container(
      key: const Key('boncukEstimateSummary'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        color: AppColors.primaryExtraLight,
        borderRadius: AppRadius.kMedium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Boncuk ile ödenecek (tahmini): ${_formatTl(estimatedValueTl)} TL',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            key: const Key('boncukEstimatedRemaining'),
            'Kalan tutar (tahmini): ${_formatTl(estimatedRemainingTl)} TL',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Kesin tutar sipariş onayında belirlenir.',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _BoncukInvalidSelectionNotice extends StatelessWidget {
  const _BoncukInvalidSelectionNotice({required this.onUseMax});

  final VoidCallback onUseMax;

  @override
  Widget build(BuildContext context) {
    const message =
        'Sepet tutarı değişti. Kullanabileceğin Boncuk miktarını yeniden seç.';
    return Semantics(
      liveRegion: true,
      label: message,
      child: Container(
        key: const Key('boncukInvalidSelectionNotice'),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.08),
          borderRadius: AppRadius.kMedium,
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded,
                size: 16, color: AppColors.error),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: AppTypography.caption.copyWith(color: AppColors.error),
              ),
            ),
            TextButton(
              onPressed: onUseMax,
              child: const Text('Maks. Kullan'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mirrors `AbacusCard`'s own `_DebtExplainer` copy pattern exactly — calm,
/// non-alarming, never the debt number, never accounting language. The
/// detailed debt figure remains visible only on the Loyalty screen.
class _BoncukDebtState extends StatelessWidget {
  const _BoncukDebtState();

  @override
  Widget build(BuildContext context) {
    const message = 'Boncuk bakiyen şu anda kullanıma uygun değil.';
    return Semantics(
      label: message,
      excludeSemantics: true,
      child: Container(
        key: const Key('boncukDebtState'),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: AppRadius.kMedium,
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded,
                size: 18, color: AppColors.textSecondary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoncukZeroState extends StatelessWidget {
  const _BoncukZeroState();

  @override
  Widget build(BuildContext context) {
    const message = 'Henüz kullanabileceğin Boncuk yok.';
    return Semantics(
      label: message,
      excludeSemantics: true,
      child: Container(
        key: const Key('boncukZeroState'),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: AppRadius.kMedium,
        ),
        child: Row(
          children: [
            const Icon(Icons.eco_outlined,
                size: 18, color: AppColors.textSecondary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
