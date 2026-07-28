import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../../shared/widgets/layout/app_section_header.dart';
import '../../domain/authorization/authorization_result.dart';
import '../../domain/authorization/pos_authorization_policy.dart';
import '../../domain/authorization/pos_authorized_action.dart';
import '../../domain/models/order_closure.dart';
import '../../domain/models/order_closure_lifecycle_status.dart';
import '../../domain/queries/closed_order_record_filter.dart';
import '../providers/order_closure_dependencies_provider.dart';

/// Lists every current [OrderClosure] record, filterable by status and by
/// which staff member closed it.
///
/// **Standalone this sprint, deliberately not wired to any route** —
/// [authorizationPolicy] has no production implementation
/// (`docs/decisions.md` ADR-012 — `PosAuthorizationPolicy` is contract-
/// only, no `NoOp` default exists), so this screen cannot be constructed
/// from anywhere in the running app today; it is directly constructible
/// for tests and for a future integration that supplies a real policy.
/// Navigating from a list item to its [ClosedAccountDetailScreen] is
/// intentionally not wired here either — that needs an `Order`-by-id
/// lookup capability this codebase doesn't have yet (only a submitted-
/// orders list, no query-by-id repository); see this sprint's final
/// report for the full integration gap.
class ClosedAccountsScreen extends ConsumerStatefulWidget {
  const ClosedAccountsScreen({
    super.key,
    required this.branchId,
    required this.authorizationPolicy,
    required this.viewerStaffId,
  });

  final String branchId;
  final PosAuthorizationPolicy authorizationPolicy;
  final String viewerStaffId;

  @override
  ConsumerState<ClosedAccountsScreen> createState() => _ClosedAccountsScreenState();
}

class _ClosedAccountsScreenState extends ConsumerState<ClosedAccountsScreen> {
  AuthorizationResult? _authorization;
  List<OrderClosure> _records = const [];
  OrderClosureLifecycleStatus? _statusFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final authorization = await widget.authorizationPolicy.authorize(
      action: PosAuthorizedAction.viewClosedAccount,
      actorStaffId: widget.viewerStaffId,
      context: {'branchId': widget.branchId},
    );
    if (!mounted) return;
    setState(() => _authorization = authorization);
    if (!authorization.granted) return;

    final all = await ref.read(orderClosureRepositoryProvider).findAllCurrent();
    if (!mounted) return;
    setState(() => _records = all);
  }

  @override
  Widget build(BuildContext context) {
    final authorization = _authorization;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Kapatılmış Hesaplar'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: authorization == null
            ? const LoadingView(message: 'Yetki kontrol ediliyor...')
            : !authorization.granted
                ? ErrorView(
                    message: authorization.reason ?? 'Bu ekranı görüntüleme yetkiniz yok.',
                  )
                : _buildList(),
      ),
    );
  }

  Widget _buildList() {
    final filter = ClosedOrderRecordFilter(lifecycleStatus: _statusFilter);
    final filtered = filter.apply(_records);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: AppSectionHeader(title: 'Kapatılmış Hesaplar'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Wrap(
            spacing: AppSpacing.xs,
            children: [
              ChoiceChip(
                label: const Text('Tümü'),
                selected: _statusFilter == null,
                onSelected: (_) => setState(() => _statusFilter = null),
              ),
              for (final status in OrderClosureLifecycleStatus.values)
                ChoiceChip(
                  label: Text(status.name),
                  selected: _statusFilter == status,
                  onSelected: (_) => setState(() => _statusFilter = status),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: filtered.isEmpty
              ? const EmptyView(
                  icon: Icons.inbox_outlined,
                  message: 'Kapatılmış hesap bulunamadı',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final closure = filtered[index];
                    return AppCard(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(closure.orderId.value, style: AppTypography.bodyLarge),
                              Text(
                                closure.closedByStaffId ?? '-',
                                style: AppTypography.bodySmall.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          Text(closure.lifecycleStatus.name, style: AppTypography.bodyMedium),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
