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

  const OrderSuccessScreen({
    super.key,
    required this.orderId,
    this.dineInBranchName,
    this.dineInTableName,
    this.takeawayBranchName,
    this.takeawayPickupTime,
  });

  bool get _isDineIn => dineInBranchName != null && dineInTableName != null;

  bool get _isTakeaway => takeawayBranchName != null;

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
