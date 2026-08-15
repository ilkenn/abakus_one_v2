import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// Step 1 — party size. Faz R.2 §5: minimum 1, maximum
/// `ReservationPolicy.maxPartySize` (server-authoritative, passed in by
/// the caller — this widget never hardcodes a bound), a large,
/// easy-to-tap +/- selector. Client validation is UX-only; `submitReservation`
/// remains the authoritative check.
class PartySizeStep extends StatelessWidget {
  const PartySizeStep({
    super.key,
    required this.value,
    required this.maxPartySize,
    required this.onChanged,
  });

  final int value;
  final int maxPartySize;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _StepperButton(
              icon: Icons.remove_rounded,
              enabled: value > 1,
              semanticLabel: 'Kişi sayısını azalt',
              onTap: () => onChanged(value - 1),
            ),
            Container(
              width: 96,
              alignment: Alignment.center,
              child: Semantics(
                label: '$value kişi',
                child: Text('$value', style: AppTypography.displayMedium),
              ),
            ),
            _StepperButton(
              icon: Icons.add_rounded,
              enabled: value < maxPartySize,
              semanticLabel: 'Kişi sayısını artır',
              onTap: () => onChanged(value + 1),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
    required this.semanticLabel,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      child: Material(
        color: enabled ? AppColors.primaryExtraLight : AppColors.surfaceVariant,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: enabled ? AppColors.primaryLight : AppColors.border,
              ),
            ),
            child: Icon(
              icon,
              size: 28,
              color: enabled ? AppColors.primary : AppColors.textDisabled,
            ),
          ),
        ),
      ),
    );
  }
}
