import 'package:flutter/material.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import 'profile_settings_row.dart';

/// "Hesap & Tercihler" — P.2 (2026-08-19). The first 4 of the old flat
/// "Hesap Ayarları" list to move into a dedicated, premium-styled group:
/// Adreslerim, Ödeme Yöntemlerim, Bildirim Ayarları, Hesap ve Verilerim.
/// Deliberately no [Divider] between rows ([ProfileSettingsRow] carries its
/// own padding + tinted icon badge instead) — "less divider-heavy" per the
/// locked P.2 brief. Destinations/navigation are unchanged from the old
/// list — this widget only takes callbacks, never owns routing itself.
class ProfileAccountPreferencesSection extends StatelessWidget {
  final VoidCallback onAddresses;
  final VoidCallback onPaymentMethods;
  final VoidCallback onNotificationSettings;
  final VoidCallback onAccountData;

  const ProfileAccountPreferencesSection({
    super.key,
    required this.onAddresses,
    required this.onPaymentMethods,
    required this.onNotificationSettings,
    required this.onAccountData,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hesap & Tercihler',
          style: AppTypography.titleMedium.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          key: const Key('accountPreferencesCard'),
          borderRadius: AppRadius.kLarge,
          boxShadow: AppShadows.card,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            children: [
              ProfileSettingsRow(
                key: const Key('pref_adreslerim'),
                icon: Icons.location_on_outlined,
                title: 'Adreslerim',
                subtitle: 'Kayıtlı adreslerini yönet',
                onTap: onAddresses,
              ),
              ProfileSettingsRow(
                key: const Key('pref_odemeYontemlerim'),
                icon: Icons.credit_card_rounded,
                title: 'Ödeme Yöntemlerim',
                subtitle: 'Kayıtlı kartlarını yönet',
                onTap: onPaymentMethods,
              ),
              ProfileSettingsRow(
                key: const Key('pref_bildirimAyarlari'),
                icon: Icons.notifications_none_rounded,
                title: 'Bildirim Ayarları',
                subtitle: 'Bildirim tercihlerini düzenle',
                onTap: onNotificationSettings,
              ),
              ProfileSettingsRow(
                key: const Key('pref_hesapVeVerilerim'),
                icon: Icons.shield_outlined,
                title: 'Hesap ve Verilerim',
                subtitle: 'Veri indirme, hesap kalıcı silme',
                onTap: onAccountData,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
