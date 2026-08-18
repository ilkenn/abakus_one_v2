import 'package:flutter/material.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import 'profile_settings_row.dart';

/// "Destek" — P.3 (2026-08-19). Exactly the 2 support-related rows moved
/// out of the old flat "Hesap Ayarları" list: Geri Bildirim Gönder and
/// Yardım ve Destek. Same premium grouped-card treatment as P.2's
/// "Hesap & Tercihler" ([ProfileSettingsRow], no dividers). Destinations
/// are unchanged — this widget only takes callbacks, never owns routing.
class ProfileSupportSection extends StatelessWidget {
  final VoidCallback onFeedback;
  final VoidCallback onHelp;

  const ProfileSupportSection({
    super.key,
    required this.onFeedback,
    required this.onHelp,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Destek',
          style: AppTypography.titleMedium.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          key: const Key('supportCard'),
          borderRadius: AppRadius.kLarge,
          boxShadow: AppShadows.card,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            children: [
              ProfileSettingsRow(
                key: const Key('support_geriBildirim'),
                icon: Icons.chat_bubble_outline_rounded,
                title: 'Geri Bildirim Gönder',
                onTap: onFeedback,
              ),
              ProfileSettingsRow(
                key: const Key('support_yardimVeDestek'),
                icon: Icons.help_outline_rounded,
                title: 'Yardım ve Destek',
                onTap: onHelp,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
