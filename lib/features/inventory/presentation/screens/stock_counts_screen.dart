import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../application/use_cases/start_stock_count.dart';
import '../../domain/stock_count.dart';
import '../providers/inventory_dependencies_provider.dart';

/// Stock Counts — Phase 7 (`docs/decisions.md` ADR-024). Lists this
/// branch's [StockCount] sessions and lets a staff member start a new
/// one. Adding count lines, submitting, and manager approval/rejection
/// happen from a dedicated count-detail flow (not built this screen —
/// this is the entry list, not the full counting workflow UI).
class StockCountsScreen extends ConsumerStatefulWidget {
  const StockCountsScreen({
    super.key,
    required this.branchId,
    this.authorizationPolicy,
    this.performedByStaffId = '',
  });

  final String branchId;
  final PosAuthorizationPolicy? authorizationPolicy;
  final String performedByStaffId;

  @override
  ConsumerState<StockCountsScreen> createState() => _StockCountsScreenState();
}

class _StockCountsScreenState extends ConsumerState<StockCountsScreen> {
  List<StockCount>? _counts;
  String? _error;
  final _locationIdController = TextEditingController(text: 'location-1');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _locationIdController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final counts = await ref
        .read(stockCountRepositoryProvider)
        .findByBranchId(widget.branchId);
    if (!mounted) return;
    setState(() => _counts = counts);
  }

  Future<void> _start() async {
    final policy = widget.authorizationPolicy;
    if (policy == null) {
      setState(() => _error = 'Yetki politikası tanımlı değil.');
      return;
    }
    final locationId = _locationIdController.text.trim();
    if (locationId.isEmpty) {
      setState(() => _error = 'Lokasyon kimliği gerekli.');
      return;
    }
    try {
      await StartStockCount(
        authorizationPolicy: policy,
        idGenerator: ref.read(stockCountIdGeneratorProvider),
        repository: ref.read(stockCountRepositoryProvider),
        auditRepository: ref.read(inventoryAuditEntryRepositoryProvider),
      )(
        branchId: widget.branchId,
        locationId: locationId,
        performedByStaffId: widget.performedByStaffId,
        performedAt: DateTime.now(),
      );
      setState(() => _error = null);
      await _load();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final counts = _counts;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Stok Sayımları'),
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
                    const Text('Yeni Sayım Başlat',
                        style: AppTypography.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _locationIdController,
                      decoration:
                          const InputDecoration(labelText: 'Lokasyon Kimliği'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (_error != null) ...[
                      Text(_error!,
                          style: AppTypography.bodySmall
                              .copyWith(color: AppColors.error)),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    OutlinedButton(
                      onPressed: _start,
                      child: const Text('Sayımı Başlat'),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: counts == null
                  ? const LoadingView(message: 'Sayımlar yükleniyor...')
                  : counts.isEmpty
                      ? const EmptyView(
                          icon: Icons.fact_check_outlined,
                          message: 'Henüz stok sayımı yapılmadı.',
                        )
                      : ListView(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg),
                          children: [
                            for (final count in counts)
                              Padding(
                                padding: const EdgeInsets.only(
                                    bottom: AppSpacing.sm),
                                child: AppCard(
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('${count.locationId} · ${count.id}',
                                          style: AppTypography.titleMedium),
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        count.status.name,
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
