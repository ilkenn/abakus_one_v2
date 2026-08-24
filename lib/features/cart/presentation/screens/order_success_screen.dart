import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/app_radius.dart';

class OrderSuccessScreen extends StatelessWidget {
  final String orderId;

  /// Dine-in table identity — when both are non-null, this screen shows
  /// "Siparişin Alındı!" + branch/table instead of the default delivery
  /// copy, and never mentions delivery/courier wording. `null` (the
  /// default) keeps this screen's original, unrelated-to-this-task
  /// delivery behavior exactly as it was.
  final String? dineInBranchName;
  final String? dineInTableName;

  /// Gel Al identity (Faz C, extended Faz D.4) — same additive-optional
  /// shape as [dineInBranchName]/[dineInTableName]: when [takeawayBranchName]
  /// is non-null, this screen shows the branch instead of the default
  /// delivery/dine-in copy. `null` (the default) leaves every other
  /// caller's behavior exactly as it was.
  final String? takeawayBranchName;

  /// `null` means an ASAP order (a Gel Al QR guest order, Faz D.4 — the
  /// backend always forces `pickupTime: null` for that scenario; there is
  /// no pickup time to show) — this screen shows "hazırlanıyor" copy
  /// instead of a specific time. Only meaningful when [takeawayBranchName]
  /// is also non-null.
  final DateTime? takeawayPickupTime;

  /// Boncuk Loyalty Program P4-E-B (2026-08-22) — additive, optional
  /// server-confirmed order/Boncuk summary. Every value here comes
  /// straight from the canonical `Order` re-read from Firestore after
  /// submission (`TakeawayCheckoutScreen._submitOrder`) — never from the
  /// pre-submit local estimate. `orderTotalMinorUnits` alone (with
  /// [boncukUsed] `null`) renders a plain total line for a no-Boncuk
  /// order; all three Boncuk fields together (only ever produced when a
  /// real redemption happened) additionally render the compact Boncuk
  /// summary. `null` (the default) leaves every existing caller's — dine-in,
  /// delivery, reservation, and any takeaway order built before this field
  /// existed — success experience exactly unchanged.
  final int? orderTotalMinorUnits;
  final int? boncukUsed;
  final int? boncukValueMinorUnits;
  final int? remainingPayableMinorUnits;

  /// Boncuk Loyalty Program P5-B (2026-08-24) — broadens the Boncuk-summary
  /// gate below to also cover a delivery order. `DeliveryCheckoutScreen` has
  /// no branch-name concept to reuse the way [takeawayBranchName] already
  /// signals takeaway (a delivery order's identity is its address, not a
  /// branch), so this is a dedicated, explicit flag rather than inferring
  /// "delivery" from the absence of the dine-in/takeaway fields — an
  /// inference that would also (wrongly) match the plain default success
  /// experience every OTHER unrelated caller still uses. `false` (the
  /// default) leaves every existing caller's behavior exactly unchanged.
  final bool isDeliveryOrder;

  const OrderSuccessScreen({
    super.key,
    required this.orderId,
    this.dineInBranchName,
    this.dineInTableName,
    this.takeawayBranchName,
    this.takeawayPickupTime,
    this.orderTotalMinorUnits,
    this.boncukUsed,
    this.boncukValueMinorUnits,
    this.remainingPayableMinorUnits,
    this.isDeliveryOrder = false,
  });

  bool get _isDineIn => dineInBranchName != null && dineInTableName != null;

  bool get _isTakeaway => takeawayBranchName != null;

  bool get _hasBoncukSummary =>
      orderTotalMinorUnits != null &&
      boncukUsed != null &&
      boncukValueMinorUnits != null &&
      remainingPayableMinorUnits != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(AppSpacing.xl),
                decoration: const BoxDecoration(
                  color: AppColors.surfaceVariant,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.primary,
                  size: 80,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                (_isDineIn || _isTakeaway)
                    ? 'Siparişin Alındı!'
                    : 'Siparişiniz Alındı!',
                style: AppTypography.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              if (_isDineIn) ...[
                Text(
                  '$dineInBranchName · $dineInTableName',
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Siparişin masana hazırlanıyor.',
                  style: AppTypography.bodyLarge.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ] else if (_isTakeaway) ...[
                Text(
                  takeawayBranchName!,
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  takeawayPickupTime != null
                      ? 'Teslim alma saati: '
                          '${takeawayPickupTime!.hour.toString().padLeft(2, '0')}:'
                          '${takeawayPickupTime!.minute.toString().padLeft(2, '0')}'
                      : 'Siparişin hazırlanıyor — kasadan teslim alabilirsin.',
                  style: AppTypography.bodyLarge.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ] else
                Text(
                  'Taptaze malzemelerle hazırlanan bowl lezzetiniz kısa sürede yola çıkacaktır.',
                  style: AppTypography.bodyLarge.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: AppSpacing.xl),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppRadius.kMedium,
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Sipariş Numarası: ',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        orderId,
                        style: AppTypography.titleMedium.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              // Boncuk Loyalty P4-E-B (2026-08-22), broadened P5-B
              // (2026-08-24) — takeaway OR delivery only, and only when a
              // real redemption happened. Every value here is
              // server-confirmed (see this class's own field doc comments)
              // — never the pre-submit local estimate. Every other
              // channel/scenario's success experience is byte-for-byte
              // unchanged (this block simply never renders for them).
              if ((_isTakeaway || isDeliveryOrder) && _hasBoncukSummary) ...[
                const SizedBox(height: AppSpacing.md),
                BoncukSuccessSummary(
                  orderTotalMinorUnits: orderTotalMinorUnits!,
                  boncukUsed: boncukUsed!,
                  boncukValueMinorUnits: boncukValueMinorUnits!,
                  remainingPayableMinorUnits: remainingPayableMinorUnits!,
                ),
              ],
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                  ),
                  child: const Text('Ana Sayfaya Dön'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Formats a kuruş (minor-units) amount as TL — a whole TL amount renders
/// with no decimals ("50 TL"); a genuinely fractional amount renders with
/// exactly two decimals ("0.50 TL"). Duplicated deliberately, not
/// extracted to a shared util — mirrors `AbacusCard`'s/`LoyaltyScreen`'s/
/// `BoncukRedemptionCard`'s own established per-file convention for this
/// exact formatter.
String _formatMinorUnitsTl(int minorUnits) {
  final valueTl = minorUnits / 100;
  final isWhole = valueTl == valueTl.roundToDouble();
  return isWhole ? valueTl.toStringAsFixed(0) : valueTl.toStringAsFixed(2);
}

/// The compact, server-confirmed Boncuk summary shown on a successful
/// order that redeemed Boncuk — Boncuk Loyalty Program P4-E-B (2026-08-22),
/// made public and reused verbatim by `ReservationConfirmationScreen` in
/// P6-B (2026-08-24) — no second, near-duplicate summary widget. Every
/// figure is a plain, already-resolved value passed in by the caller
/// (sourced from the canonical re-read `Order`, never the pre-submit
/// estimate) — this widget performs no computation beyond minor-units-to-TL
/// formatting.
class BoncukSuccessSummary extends StatelessWidget {
  const BoncukSuccessSummary({
    super.key,
    required this.orderTotalMinorUnits,
    required this.boncukUsed,
    required this.boncukValueMinorUnits,
    required this.remainingPayableMinorUnits,
  });

  final int orderTotalMinorUnits;
  final int boncukUsed;
  final int boncukValueMinorUnits;
  final int remainingPayableMinorUnits;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('orderSuccessBoncukSummary'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: const BoxDecoration(
        color: AppColors.primaryExtraLight,
        borderRadius: AppRadius.kMedium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: '$boncukUsed Boncuk kullanıldı',
            excludeSemantics: true,
            child: Row(
              children: [
                const Icon(Icons.eco_rounded,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  '$boncukUsed Boncuk kullanıldı',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _SummaryRow(
            label: 'Sipariş Tutarı',
            value: '${_formatMinorUnitsTl(orderTotalMinorUnits)} TL',
          ),
          _SummaryRow(
            label: 'Boncuk ile Ödenen',
            value: '${_formatMinorUnitsTl(boncukValueMinorUnits)} TL',
          ),
          _SummaryRow(
            label: 'Kalan Tutar',
            value: '${_formatMinorUnitsTl(remainingPayableMinorUnits)} TL',
            emphasized: true,
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final valueStyle = emphasized
        ? AppTypography.bodyMedium.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          )
        : AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Text(value, style: valueStyle),
        ],
      ),
    );
  }
}
