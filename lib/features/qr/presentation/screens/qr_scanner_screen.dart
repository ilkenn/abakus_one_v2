import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';

/// Entry point for the bottom nav's "QR ile Sipariş" action.
///
/// There is no camera/QR-scanning package in this project yet (see
/// `pubspec.yaml`) and no backend to resolve a scanned code against — the
/// domain models this flow will eventually drive already exist
/// (`lib/features/qr/domain/models/`: `TableQrCode`, `RestaurantTable`,
/// `TableSession`, `GuestSession`) but nothing populates or resolves them.
/// Rather than fake a scan-and-connect flow with no real table behind it,
/// this screen honestly explains the feature and its primary action reports
/// that live scanning isn't available yet — no simulated success state.
class QrScannerScreen extends StatelessWidget {
  const QrScannerScreen({super.key});

  void _showNotAvailableYet(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Kamera ile QR tarama bu sürümde henüz aktif değil. Yakında eklenecek.',
        ),
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR ile Sipariş'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Center(
              child: Container(
                width: 120,
                height: 120,
                decoration: const BoxDecoration(
                  color: AppColors.primaryExtraLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.qr_code_scanner_rounded,
                  color: AppColors.primary,
                  size: 56,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const Text(
              'Masandaki QR Kodu Okut',
              style: AppTypography.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Menüyü görüntüle, siparişini masandan ver, beklemeden öde.',
              style: AppTypography.bodyLarge.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text(
              'Nasıl Çalışır?',
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const AppCard(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  _StepRow(
                    icon: Icons.qr_code_rounded,
                    title: 'QR kodu tara',
                    description: 'Masandaki kodu kameranla okut.',
                  ),
                  SizedBox(height: AppSpacing.lg),
                  _StepRow(
                    icon: Icons.restaurant_menu_rounded,
                    title: 'Menüden seç',
                    description: 'Masana özel menüyü incele, sepetini oluştur.',
                  ),
                  SizedBox(height: AppSpacing.lg),
                  _StepRow(
                    icon: Icons.check_circle_outline_rounded,
                    title: 'Siparişini onayla',
                    description:
                        'Siparişin doğrudan mutfağa iletilsin, masanda bekle.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showNotAvailableYet(context),
                icon: const Icon(Icons.camera_alt_rounded),
                label: const Text('QR Kodu Tara'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.md,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Kamera erişimi bu sürümde aktif değildir.',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _StepRow({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: AppColors.surfaceVariant,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppColors.primary, size: 20),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.bodyLarge.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
