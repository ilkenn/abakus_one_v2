import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// CR.1.2 — the two steps of "Profilini Tamamla": the mandatory form,
/// then the optional profile photo. Deliberately just two values, not a
/// generic step-count — this indicator is purpose-built for this one
/// flow, not a reusable wizard component (no other flow in this app has
/// asked for one yet).
enum OnboardingStep { info, photo }

/// A compact "1 — Bilgilerin, 2 — Profil Fotoğrafın" progress header.
/// Built from real widgets and existing design tokens only — no external
/// stepper/wizard package, no `AnimatedContainer`-heavy transition (the
/// locked instruction: "avoid unnecessary animation complexity").
class OnboardingStepIndicator extends StatelessWidget {
  const OnboardingStepIndicator({super.key, required this.currentStep});

  final OnboardingStep currentStep;

  @override
  Widget build(BuildContext context) {
    final infoIsPast = currentStep == OnboardingStep.photo;
    return Semantics(
      label: currentStep == OnboardingStep.info
          ? 'Adım 1 / 2: Bilgilerin'
          : 'Adım 2 / 2: Profil Fotoğrafın',
      child: ExcludeSemantics(
        child: Row(
          children: [
            Expanded(
              child: _StepLabel(
                number: 1,
                label: 'Bilgilerin',
                isActive: currentStep == OnboardingStep.info,
                isDone: infoIsPast,
              ),
            ),
            _StepConnector(isDone: infoIsPast),
            Expanded(
              child: _StepLabel(
                number: 2,
                label: 'Profil Fotoğrafın',
                isActive: currentStep == OnboardingStep.photo,
                isDone: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepLabel extends StatelessWidget {
  const _StepLabel({
    required this.number,
    required this.label,
    required this.isActive,
    required this.isDone,
  });

  final int number;
  final String label;
  final bool isActive;
  final bool isDone;

  @override
  Widget build(BuildContext context) {
    final highlighted = isActive || isDone;
    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: highlighted ? AppColors.primary : AppColors.surfaceVariant,
            border: Border.all(
              color: highlighted ? AppColors.primary : AppColors.border,
            ),
          ),
          child: isDone
              ? const Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: AppColors.onPrimary,
                )
              : Text(
                  '$number',
                  style: AppTypography.labelMedium.copyWith(
                    color: highlighted
                        ? AppColors.onPrimary
                        : AppColors.textSecondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          textAlign: TextAlign.center,
          style: AppTypography.bodySmall.copyWith(
            color:
                highlighted ? AppColors.textPrimary : AppColors.textSecondary,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

class _StepConnector extends StatelessWidget {
  const _StepConnector({required this.isDone});

  final bool isDone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: AppSpacing.lg + AppSpacing.xs,
      ),
      child: SizedBox(
        width: AppSpacing.xl,
        height: 2,
        child: ColoredBox(
          color: isDone ? AppColors.primary : AppColors.border,
        ),
      ),
    );
  }
}
