import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../address_search/presentation/screens/map_first_address_screen.dart';
import '../../../orders/domain/models/saved_address.dart';
import '../../../orders/presentation/providers/saved_address_providers.dart';

/// Paket Servis P.3 — the "Adresi Değiştir" picker `DeliveryCheckoutScreen`
/// opens. **Distinct from `AddressesScreen`** (the profile CRUD screen):
/// this screen only ever selects an address for the current checkout — it
/// never edits/deletes, and returns the chosen [SavedAddress] via
/// `Navigator.pop`.
///
/// Only a [SavedAddress.isDeliveryAuthorized] (verified) address is
/// selectable — `submitDeliveryOrder` would reject an unverified one
/// server-side regardless, so an unverified entry is shown, disabled, with
/// an explanatory note rather than silently omitted (the customer should
/// still see it exists).
class DeliveryAddressSelectionScreen extends ConsumerWidget {
  const DeliveryAddressSelectionScreen({super.key});

  Future<void> _openCreateFlow(BuildContext context, WidgetRef ref) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => const MapFirstAddressScreen()),
    );
    if (saved == true) {
      await ref.read(savedAddressListProvider.notifier).refresh();
    }
  }

  String _formattedAddressOf(SavedAddress address) {
    if (address.formattedAddress != null) return address.formattedAddress!;
    final parts = [
      if (address.neighborhoodName != null) address.neighborhoodName,
      if (address.streetName != null) address.streetName,
      if (address.buildingNo != null) 'No:${address.buildingNo}',
      'Daire:${address.apartmentNo}',
      if (address.districtName != null) address.districtName,
    ];
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addressesAsync = ref.watch(savedAddressListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Teslimat Adresi Seç'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, color: AppColors.primary),
            onPressed: () => _openCreateFlow(context, ref),
          ),
        ],
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: addressesAsync.when(
          loading: () => const LoadingView(message: 'Adresler yükleniyor...'),
          error: (error, stackTrace) => ErrorView(
            message: 'Adresler yüklenemedi. Lütfen tekrar deneyin.',
            retryLabel: 'Tekrar Dene',
            onRetry: () =>
                ref.read(savedAddressListProvider.notifier).refresh(),
          ),
          data: (addresses) => addresses.isEmpty
              ? EmptyView(
                  icon: Icons.location_off_rounded,
                  message: 'Kayıtlı adresiniz bulunmuyor.',
                  actionLabel: 'Yeni Adres Ekle',
                  onAction: () => _openCreateFlow(context, ref),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  itemCount: addresses.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: AppSpacing.md),
                  itemBuilder: (context, index) {
                    final address = addresses[index];
                    final isSelectable = address.isDeliveryAuthorized;
                    return InkWell(
                      onTap: isSelectable
                          ? () => Navigator.pop(context, address)
                          : null,
                      borderRadius: AppRadius.kMedium,
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: isSelectable
                              ? AppColors.surface
                              : AppColors.surfaceVariant,
                          borderRadius: AppRadius.kMedium,
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  address.label,
                                  style: AppTypography.titleMedium.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (address.isDefault) ...[
                                  const SizedBox(width: AppSpacing.sm),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.sm,
                                      vertical: 2,
                                    ),
                                    decoration: const BoxDecoration(
                                      color: AppColors.primaryExtraLight,
                                      borderRadius: AppRadius.kSmall,
                                    ),
                                    child: Text(
                                      'Varsayılan',
                                      style: AppTypography.bodySmall.copyWith(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              _formattedAddressOf(address),
                              style: AppTypography.bodyMedium.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            if (!isSelectable) ...[
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                'Bu adres henüz doğrulanmadı, teslimat için kullanılamaz.',
                                style: AppTypography.bodySmall.copyWith(
                                  color: AppColors.error,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
