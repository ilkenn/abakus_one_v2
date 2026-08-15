import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../address_search/presentation/screens/map_first_address_screen.dart';
import '../../../orders/data/saved_address_exception.dart';
import '../../../orders/domain/models/saved_address.dart';
import '../../../orders/presentation/providers/saved_address_providers.dart';

/// **The canonical customer-visible saved-address list** — Faz P.2.1.2.
/// Reads [savedAddressListProvider] (backed by the real
/// `customerAddresses` Firestore collection via [SavedAddressRepository]),
/// **not** the legacy in-memory `addressesProvider`/`AddressModel` — that
/// mock source is no longer read by this screen at all (`docs/decisions
/// .md` Faz P.2.1.2 closes the gap Faz P.2.1.1 disclosed). Both "Yeni
/// Adres Ekle" and the per-address edit action route to
/// [MapFirstAddressScreen] — the map-first canonical flow (UX
/// correction, same phase) — never the legacy `AddressFormScreen`; a
/// successful save there triggers [SavedAddressListNotifier.refresh] so
/// the list updates without an app restart.
class AddressesScreen extends ConsumerWidget {
  const AddressesScreen({super.key});

  Future<void> _openCreateFlow(BuildContext context, WidgetRef ref) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => const MapFirstAddressScreen(),
      ),
    );
    if (saved == true) {
      await ref.read(savedAddressListProvider.notifier).refresh();
    }
  }

  Future<void> _openEditFlow(
    BuildContext context,
    WidgetRef ref,
    SavedAddress address,
  ) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => MapFirstAddressScreen(
          existingAddressId: address.id,
          initialLatitude: address.latitude,
          initialLongitude: address.longitude,
        ),
      ),
    );
    if (saved == true) {
      await ref.read(savedAddressListProvider.notifier).refresh();
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    SavedAddress address,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Adresi Sil'),
        content: Text(
          '"${address.label}" adresini silmek istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(savedAddressRepositoryProvider).delete(address.id);
      await ref.read(savedAddressListProvider.notifier).refresh();
    } on SavedAddressException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
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
        title: const Text('Adreslerim'),
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
              ? const EmptyView(
                  icon: Icons.location_off_rounded,
                  message: 'Kayıtlı adresiniz bulunmuyor.',
                )
              : RefreshIndicator(
                  onRefresh: () =>
                      ref.read(savedAddressListProvider.notifier).refresh(),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    itemCount: addresses.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: AppSpacing.md),
                    itemBuilder: (context, index) {
                      final address = addresses[index];
                      return Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: AppRadius.kMedium,
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                          style:
                                              AppTypography.bodySmall.copyWith(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined,
                                          size: 20),
                                      onPressed: () =>
                                          _openEditFlow(context, ref, address),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 20,
                                        color: AppColors.error,
                                      ),
                                      onPressed: () =>
                                          _confirmDelete(context, ref, address),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              _formattedAddressOf(address),
                              style: AppTypography.bodyMedium.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ),
    );
  }
}
