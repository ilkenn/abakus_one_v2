import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/app_radius.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  void _showContactSnackBar(BuildContext context, String channel) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$channel destek hattına yönlendiriliyorsunuz...'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, String>> faqs = [
      {
        'category': 'Sipariş ve Teslimat',
        'question': 'Siparişim ne kadar sürede teslim edilir?',
        'answer':
            'Siparişleriniz seçtiğiniz teslimat bölgesine ve yoğunluğa bağlı olarak ortalama 20-35 dakika içerisinde taze olarak ulaştırılır.',
      },
      {
        'category': 'Ödeme',
        'question': 'Hangi ödeme yöntemleri geçerlidir?',
        'answer':
            'Uygulama üzerinden kredi kartı/banka kartı ile online ödeme yapabilir veya kapıda nakit/kredi kartı seçeneklerini kullanabilirsiniz.',
      },
      {
        'category': 'İade ve İptal',
        'question': 'Siparişimi nasıl iptal edebilirim?',
        'answer':
            'Hazırlanmaya başlanmayan siparişlerinizi Siparişlerim ekranından iptal edebilir veya destek hattımızla hızlıca iletişime geçebilirsiniz.',
      },
      {
        'category': 'Hesap ve Üyelik',
        'question': 'Sadakat boncukları ne işe yarar?',
        'answer':
            'Her siparişinizde kazandığınız abaküs sadakat boncuklarını biriktirerek ücretsiz bowl veya sürpriz indirim kuponları kazanabilirsiniz.',
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Yardım ve Destek'),
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
            Text(
              'Sık Sorulan Sorular',
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              decoration: BoxDecoration(
                borderRadius: AppRadius.kMedium,
                border: Border.all(color: AppColors.border),
              ),
              child: Material(
                color: AppColors.surface,
                borderRadius: AppRadius.kMedium,
                clipBehavior: Clip.antiAlias,
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: faqs.length,
                  separatorBuilder: (context, index) =>
                      const Divider(color: AppColors.border, height: 1),
                  itemBuilder: (context, index) {
                    final faq = faqs[index];
                    return ExpansionTile(
                      title: Text(
                        faq['question']!,
                        style: AppTypography.bodyLarge.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        faq['category']!,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                      iconColor: AppColors.primary,
                      collapsedIconColor: AppColors.textSecondary,
                      childrenPadding: const EdgeInsets.only(
                        left: AppSpacing.md,
                        right: AppSpacing.md,
                        bottom: AppSpacing.md,
                      ),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      shape: const Border(),
                      collapsedShape: const Border(),
                      children: [
                        Text(
                          faq['answer']!,
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Bizimle İletişime Geçin',
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              decoration: BoxDecoration(
                borderRadius: AppRadius.kMedium,
                border: Border.all(color: AppColors.border),
              ),
              child: Material(
                color: AppColors.surface,
                borderRadius: AppRadius.kMedium,
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.phone_rounded,
                        color: AppColors.primary,
                      ),
                      title: const Text(
                        'Müşteri Hizmetleri',
                        style: AppTypography.bodyLarge,
                      ),
                      subtitle: const Text(
                        '0850 000 00 00',
                        style: AppTypography.bodyMedium,
                      ),
                      trailing: const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.textSecondary,
                      ),
                      onTap: () => _showContactSnackBar(context, 'Telefon'),
                    ),
                    const Divider(color: AppColors.border, height: 1),
                    ListTile(
                      leading: const Icon(
                        Icons.email_rounded,
                        color: AppColors.primary,
                      ),
                      title: const Text(
                        'E-posta Destek',
                        style: AppTypography.bodyLarge,
                      ),
                      subtitle: const Text(
                        'destek@abakusbowl.com',
                        style: AppTypography.bodyMedium,
                      ),
                      trailing: const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.textSecondary,
                      ),
                      onTap: () => _showContactSnackBar(context, 'E-posta'),
                    ),
                    const Divider(color: AppColors.border, height: 1),
                    ListTile(
                      leading: const Icon(
                        Icons.chat_rounded,
                        color: AppColors.primary,
                      ),
                      title: const Text(
                        'WhatsApp Canlı Destek',
                        style: AppTypography.bodyLarge,
                      ),
                      subtitle: const Text(
                        'Hızlı ve anlık çözüm',
                        style: AppTypography.bodyMedium,
                      ),
                      trailing: const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.textSecondary,
                      ),
                      onTap: () => _showContactSnackBar(context, 'WhatsApp'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
