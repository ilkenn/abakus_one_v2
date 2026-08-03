import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../application/use_cases/create_supplier.dart';
import '../../domain/supplier.dart';
import '../providers/purchasing_dependencies_provider.dart';

/// Supplier Catalog — Phase 7 (`docs/decisions.md` ADR-024). Lists
/// this organization's [Supplier]s and lets a manager add a new one.
/// Supplier-product mapping, pricing, and purchase orders are managed
/// from their own dedicated flows once a supplier exists here.
class SuppliersScreen extends ConsumerStatefulWidget {
  const SuppliersScreen({
    super.key,
    required this.organizationId,
    this.authorizationPolicy,
    this.performedByStaffId = '',
  });

  final String organizationId;
  final PosAuthorizationPolicy? authorizationPolicy;
  final String performedByStaffId;

  @override
  ConsumerState<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends ConsumerState<SuppliersScreen> {
  List<Supplier>? _suppliers;
  String? _error;
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final suppliers = await ref
        .read(supplierRepositoryProvider)
        .findByOrganizationId(widget.organizationId);
    if (!mounted) return;
    setState(() => _suppliers = suppliers);
  }

  Future<void> _create() async {
    final policy = widget.authorizationPolicy;
    if (policy == null) {
      setState(() => _error = 'Yetki politikası tanımlı değil.');
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Tedarikçi adı gerekli.');
      return;
    }
    try {
      await CreateSupplier(
        authorizationPolicy: policy,
        idGenerator: ref.read(supplierIdGeneratorProvider),
        repository: ref.read(supplierRepositoryProvider),
        auditRepository: ref.read(supplierAuditEntryRepositoryProvider),
      )(
        organizationId: widget.organizationId,
        name: name,
        performedByStaffId: widget.performedByStaffId,
        performedAt: DateTime.now(),
      );
      _nameController.clear();
      setState(() => _error = null);
      await _load();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = _suppliers;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Tedarikçiler'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: AppCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Yeni Tedarikçi',
                        style: AppTypography.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: 'Ad'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (_error != null) ...[
                      Text(_error!,
                          style: AppTypography.bodySmall
                              .copyWith(color: AppColors.error)),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    OutlinedButton(
                      onPressed: _create,
                      child: const Text('Tedarikçi Ekle'),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: suppliers == null
                  ? const LoadingView(message: 'Tedarikçiler yükleniyor...')
                  : suppliers.isEmpty
                      ? const EmptyView(
                          icon: Icons.local_shipping_outlined,
                          message: 'Henüz tedarikçi eklenmedi.',
                        )
                      : ListView(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg),
                          children: [
                            for (final supplier in suppliers)
                              Padding(
                                padding: const EdgeInsets.only(
                                    bottom: AppSpacing.sm),
                                child: AppCard(
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(supplier.name,
                                          style: AppTypography.titleMedium),
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        supplier.isActive ? 'Aktif' : 'Pasif',
                                        style: AppTypography.bodySmall.copyWith(
                                            color: AppColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
