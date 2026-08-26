import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../campaigns/domain/models/campaign.dart';

/// Server-Authoritative Campaign Engine P8-C (2026-08-25) — the minimal
/// Takeaway checkout widget for selecting one campaign from the customer's
/// real, server-authoritative active-campaign list
/// (`activeCampaignsProvider` / `getCustomerActiveCampaigns`). Mirrors
/// `CatalogRewardCard`'s exact shape/discipline — a presentational (dumb)
/// widget that never calls the backend itself and never invents a
/// campaign; every entry shown here came from a real
/// `getCustomerActiveCampaigns` response.
///
/// **Client-side eligibility shown here is a best-effort HINT ONLY** — the
/// server (`submitTakeawayOrder.ts`) re-validates every eligibility rule
/// (tenant, active/archived, schedule, minimum basket, product/category
/// targeting, usage limits, ...) from trusted server state at submission
/// time. This widget can only see what `getCustomerActiveCampaigns` already
/// exposes (no live usage-count data is exposed to the client at all — a
/// usage-exhausted campaign therefore cannot be flagged here in advance, it
/// still shows selectable and is rejected server-side on submit, exactly
/// like a client-side Boncuk-max estimate can go stale). Never treated as
/// authoritative anywhere in this widget or its caller.
///
/// **Mutual exclusivity with cash Boncuk redemption / a catalog reward** is
/// enforced by the CALLER (`TakeawayCheckoutScreen`), not this widget —
/// see that screen's own selection-state handling. This card only
/// renders/selects; it holds no state of its own.
class CampaignSelectionCard extends StatelessWidget {
  const CampaignSelectionCard({
    super.key,
    required this.campaignsAsync,
    required this.commercialChannel,
    required this.cartProductIds,
    required this.cartTotalPriceTl,
    required this.selectedCampaignId,
    required this.otherBenefitActive,
    required this.controlsFrozen,
    required this.onSelect,
    required this.onRetry,
  });

  final AsyncValue<List<Campaign>> campaignsAsync;

  /// The real, server-derived commercial channel this checkout is
  /// submitting under (`"takeaway"`/`"delivery"`, matching
  /// `CanonicalCommercialChannel` server-side) — this card is reused
  /// verbatim by every channel's own checkout screen, so the channel is
  /// always supplied by the caller, never hardcoded here (a P8-C.1 fix:
  /// this was originally hardcoded to `"takeaway"`, silently filtering out
  /// every delivery-eligible campaign when the widget was first reused on
  /// `DeliveryCheckoutScreen`).
  final String commercialChannel;
  final Set<String> cartProductIds;

  /// The cart's own approximate TL total (same non-authoritative estimate
  /// this screen already labels "tahminidir" elsewhere) — used only to show
  /// a best-effort "minimum basket not met" hint; never sent to the server.
  final double cartTotalPriceTl;

  /// The customer's own explicit campaign choice — `null` means none
  /// selected. Never silently chosen/cleared by this widget.
  final String? selectedCampaignId;

  /// `true` when cash Boncuk redemption OR a catalog reward is currently
  /// the customer's selected benefit — this card disables itself entirely
  /// while that is true (one order = maximum one benefit), rather than
  /// allowing a doomed selection the server would reject anyway.
  final bool otherBenefitActive;

  final bool controlsFrozen;

  /// Tapping an already-selected campaign calls this with `null`
  /// (deselect); tapping a different one calls this with its `campaignId`.
  final ValueChanged<String?> onSelect;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (otherBenefitActive) return const SizedBox.shrink();

    return campaignsAsync.when(
      loading: () => const _LeadingGap(child: _CampaignCardSkeleton()),
      error: (error, stackTrace) =>
          _LeadingGap(child: _CampaignCardError(onRetry: onRetry)),
      data: (campaigns) {
        final eligibleCampaigns = [
          for (final campaign in campaigns)
            if (campaign.isEligibleForChannel(commercialChannel)) campaign,
        ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        // No leading gap at all when there's genuinely nothing to show —
        // unlike `CatalogRewardCard`'s own pre-existing sibling pattern
        // (which keeps an unconditional gap above it even when empty), this
        // card's gap is self-contained precisely so an empty campaign list
        // contributes zero extra layout height to the checkout screen.
        if (eligibleCampaigns.isEmpty) return const SizedBox.shrink();

        final cartTotalMinorUnits = (cartTotalPriceTl * 100).round();

        return _LeadingGap(
          child: AppCard(
            key: const Key('campaignSelectionCard'),
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kampanya Kullan',
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final campaign in eligibleCampaigns)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _CampaignTile(
                      key: Key('campaignTile-${campaign.campaignId}'),
                      campaign: campaign,
                      unavailableReason: _unavailableReason(
                        campaign,
                        cartTotalMinorUnits: cartTotalMinorUnits,
                        cartProductIds: cartProductIds,
                      ),
                      isSelected: selectedCampaignId == campaign.campaignId,
                      enabled: !controlsFrozen,
                      onTap: () => onSelect(
                        selectedCampaignId == campaign.campaignId
                            ? null
                            : campaign.campaignId,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Best-effort, non-authoritative unavailability hint — `null` means "no
  /// known reason this would fail," never a guarantee of success. See this
  /// class's own doc comment for what this can and cannot check.
  String? _unavailableReason(
    Campaign campaign, {
    required int cartTotalMinorUnits,
    required Set<String> cartProductIds,
  }) {
    final minimumBasket = campaign.minimumBasketMinorUnits;
    if (minimumBasket != null && cartTotalMinorUnits < minimumBasket) {
      final minimumTl = minimumBasket / 100;
      final formatted = minimumTl == minimumTl.roundToDouble()
          ? minimumTl.toStringAsFixed(0)
          : minimumTl.toStringAsFixed(2);
      return 'Bu kampanya için sepet tutarın en az $formatted TL olmalı.';
    }

    final eligibleProductIds = campaign.eligibleProductIds;
    if (eligibleProductIds != null &&
        eligibleProductIds.isNotEmpty &&
        !eligibleProductIds.any(cartProductIds.contains)) {
      return 'Sepetinde bu kampanyaya uygun bir ürün yok.';
    }

    final rule = campaign.rule;
    switch (rule.mechanic) {
      case 'buyXGetY':
        final triggerProductId = rule.triggerProductId;
        if (triggerProductId != null &&
            !cartProductIds.contains(triggerProductId)) {
          return 'Sepetinde bu kampanyaya uygun bir ürün yok.';
        }
        break;
      case 'freeProduct':
        final freeProductId = rule.freeProductId;
        if (freeProductId != null && !cartProductIds.contains(freeProductId)) {
          return 'Sepetinde bu kampanyaya uygun bir ürün yok.';
        }
        break;
      case 'percentage':
      case 'fixedAmount':
        if (rule.scopeKind == 'product') {
          final scopeProductId = rule.scopeProductId;
          if (scopeProductId != null &&
              !cartProductIds.contains(scopeProductId)) {
            return 'Sepetinde bu kampanyaya uygun bir ürün yok.';
          }
        }
        // A category-scoped rule cannot be checked client-side — `CartItem`
        // carries no `categoryId` (see this widget's own doc comment on
        // client-side limits). Left selectable; the server is the final
        // authority.
        break;
    }

    return null;
  }
}

class _CampaignTile extends StatelessWidget {
  const _CampaignTile({
    super.key,
    required this.campaign,
    required this.unavailableReason,
    required this.isSelected,
    required this.enabled,
    required this.onTap,
  });

  final Campaign campaign;
  final String? unavailableReason;
  final bool isSelected;
  final bool enabled;
  final VoidCallback onTap;

  bool get _tileEnabled => enabled && unavailableReason == null;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _tileEnabled ? onTap : null,
      borderRadius: AppRadius.kMedium,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryExtraLight : AppColors.surface,
          borderRadius: AppRadius.kMedium,
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isSelected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: unavailableReason != null
                  ? AppColors.textSecondary.withValues(alpha: 0.4)
                  : (isSelected ? AppColors.primary : AppColors.textSecondary),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    campaign.title,
                    style: AppTypography.bodyLarge.copyWith(
                      color: unavailableReason != null
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    campaign.description,
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  if (unavailableReason != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      unavailableReason!,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Self-contained leading spacer — makes the gap part of whatever this card
/// actually renders, rather than the CALLER (`TakeawayCheckoutScreen`)
/// placing an unconditional `SizedBox` before it. A truly-empty campaign
/// list therefore contributes zero extra layout height to the checkout
/// screen, never an orphaned gap above nothing.
class _LeadingGap extends StatelessWidget {
  const _LeadingGap({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [const SizedBox(height: AppSpacing.lg), child],
    );
  }
}

class _CampaignCardSkeleton extends StatelessWidget {
  const _CampaignCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: const Key('campaignSelectionCardSkeleton'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'Kampanyalar yükleniyor...',
            style: AppTypography.bodyMedium
                .copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _CampaignCardError extends StatelessWidget {
  const _CampaignCardError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: const Key('campaignSelectionCardError'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Kampanyalara şu anda ulaşılamıyor. Kampanya kullanmadan devam '
              'edebilirsin.',
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Tekrar dene')),
        ],
      ),
    );
  }
}
