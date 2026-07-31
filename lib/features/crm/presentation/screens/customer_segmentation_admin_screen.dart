import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../domain/segmentation/customer.dart';
import '../../domain/segmentation/customer_category.dart';
import '../providers/crm_dependencies_provider.dart';

/// Administrator customer list with a category filter — Sprint 5D Part 1,
/// the "administrator must be able to filter by category" requirement.
class CustomerSegmentationAdminScreen extends ConsumerStatefulWidget {
  const CustomerSegmentationAdminScreen({super.key});

  @override
  ConsumerState<CustomerSegmentationAdminScreen> createState() =>
      _CustomerSegmentationAdminScreenState();
}

class _CustomerSegmentationAdminScreenState
    extends ConsumerState<CustomerSegmentationAdminScreen> {
  List<Customer>? _customers;
  CustomerCategory? _filter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final repository = ref.read(customerRepositoryProvider);
    final customers = _filter == null
        ? await repository.findAll()
        : await repository.findByCategory(_filter!);
    if (!mounted) return;
    setState(() => _customers = customers);
  }

  static String _categoryLabel(CustomerCategory category) {
    switch (category) {
      case CustomerCategory.student:
        return 'Öğrenci';
      case CustomerCategory.bankEmployee:
        return 'Banka Çalışanı';
      case CustomerCategory.officeWorker:
        return 'Ofis Çalışanı';
      case CustomerCategory.softwareTechnology:
        return 'Yazılım / Teknoloji';
      case CustomerCategory.healthcare:
        return 'Sağlık';
      case CustomerCategory.education:
        return 'Eğitim';
      case CustomerCategory.selfEmployed:
        return 'Serbest Meslek';
      case CustomerCategory.hospitality:
        return 'Ağırlama';
      case CustomerCategory.logistics:
        return 'Lojistik';
      case CustomerCategory.other:
        return 'Diğer';
      case CustomerCategory.preferNotToSay:
        return 'Belirtmek İstemiyorum';
    }
  }

  @override
  Widget build(BuildContext context) {
    final customers = _customers;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Müşteri Segmentasyonu'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: customers == null
            ? const LoadingView(message: 'Müşteriler yükleniyor...')
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                          labelText: 'Kategoriye göre filtrele'),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<CustomerCategory?>(
                          value: _filter,
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem(
                                value: null, child: Text('Tümü')),
                            for (final category in CustomerCategory.values)
                              DropdownMenuItem(
                                value: category,
                                child: Text(_categoryLabel(category)),
                              ),
                          ],
                          onChanged: (value) {
                            setState(() => _filter = value);
                            _load();
                          },
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: customers.isEmpty
                        ? const EmptyView(
                            icon: Icons.people_outline,
                            message: 'Kayıtlı müşteri bulunamadı.',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            itemCount: customers.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: AppSpacing.sm),
                            itemBuilder: (context, index) {
                              final customer = customers[index];
                              return AppCard(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(customer.displayName,
                                              style: AppTypography.bodyMedium),
                                          Text(customer.phoneNumber,
                                              style: AppTypography.bodySmall
                                                  .copyWith(
                                                      color: AppColors
                                                          .textSecondary)),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      customer.category == null
                                          ? '-'
                                          : _categoryLabel(customer.category!),
                                      style: AppTypography.bodySmall,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
