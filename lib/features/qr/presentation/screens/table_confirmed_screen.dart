import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../navigation/presentation/providers/navigation_provider.dart';

/// Shown once for ~a beat after a QR scan successfully opens a table
/// session — confirms *which* table before handing the customer off to the
/// menu. Deliberately simple/functional (this task is "functionality
/// first," per its own brief — a premium version of this moment is a
/// separate, later visual pass).
class TableConfirmedScreen extends ConsumerWidget {
  final String branchName;
  final String tableName;

  const TableConfirmedScreen({
    super.key,
    required this.branchName,
    required this.tableName,
  });

  void _continueToMenu(BuildContext context, WidgetRef ref) {
    ref.read(navigationProvider.notifier).selectTab(AppTab.menu);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  color: AppColors.primaryExtraLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.primary,
                  size: 72,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                branchName,
                style: AppTypography.titleMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                tableName,
                style: AppTypography.headlineLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Masan hazır.',
                style: AppTypography.bodyLarge.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _continueToMenu(context, ref),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                  ),
                  child: const Text('Menüyü Görüntüle'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
