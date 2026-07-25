import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/app_radius.dart';
import '../providers/saved_cards_provider.dart';
import 'card_form_screen.dart';

class SavedCardsScreen extends ConsumerWidget {
  const SavedCardsScreen({super.key});

  void _showDeleteDialog(BuildContext context, WidgetRef ref, String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kartı Sil'),
        content: const Text(
          'Bu ödeme yöntemini kalıcı olarak silmek istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () {
              ref.read(savedCardsProvider.notifier).deleteCard(id);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Kart başarıyla silindi.')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(savedCardsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ödeme Yöntemlerim'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: cards.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.credit_card_off_rounded,
                            size: 64,
                            color: AppColors.textSecondary.withValues(
                              alpha: 0.5,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'Kayıtlı kartınız bulunmuyor.',
                            style: AppTypography.titleMedium.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      itemCount: cards.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: AppSpacing.md),
                      itemBuilder: (context, index) {
                        final card = cards[index];

                        return Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: AppRadius.kMedium,
                            border: Border.all(
                              color: card.isDefault
                                  ? AppColors.primary
                                  : AppColors.border,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                card.cardBrand == 'Visa'
                                    ? Icons.credit_card_rounded
                                    : Icons.credit_card_sharp,
                                color: AppColors.primary,
                                size: 32,
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          '•••• •••• •••• ${card.lastFourDigits}',
                                          style: AppTypography.titleMedium
                                              .copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (card.isDefault) ...[
                                          const SizedBox(width: AppSpacing.xs),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.primary
                                                  .withValues(alpha: 0.1),
                                              borderRadius: AppRadius.kSmall,
                                            ),
                                            child: const Text(
                                              'Varsayılan',
                                              style: TextStyle(
                                                color: AppColors.primary,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    Text(
                                      card.cardHolderName,
                                      style: AppTypography.bodyMedium,
                                    ),
                                    Text(
                                      '${card.expiryMonth}/${card.expiryYear} | ${card.cardBrand}',
                                      style: AppTypography.bodySmall.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (!card.isDefault)
                                IconButton(
                                  icon: const Icon(
                                    Icons.check_circle_outline_rounded,
                                    color: AppColors.textSecondary,
                                  ),
                                  onPressed: () => ref
                                      .read(savedCardsProvider.notifier)
                                      .setDefaultCard(card.id),
                                  tooltip: 'Varsayılan Yap',
                                ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: Colors.redAccent,
                                ),
                                onPressed: () =>
                                    _showDeleteDialog(context, ref, card.id),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add_rounded),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CardFormScreen(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                ),
                label: const Text('Yeni Kart Ekle'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
