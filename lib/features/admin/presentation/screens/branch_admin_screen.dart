import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../application/use_cases/set_branch_emergency_stop.dart';
import '../../application/use_cases/set_branch_status.dart';
import '../../domain/organization/branch.dart';
import '../../domain/organization/branch_status.dart';
import '../providers/admin_dependencies_provider.dart';

/// Branch administration — Phase 6D (`docs/decisions.md` ADR-023).
/// "Minimum safe organization/tenant boundary": lists every `Branch`,
/// its status, and its emergency-stop state; supports changing status
/// and triggering/clearing the emergency stop. Creating new
/// organizations/restaurants/branches is intentionally left to a future,
/// more complete onboarding flow — this screen manages the seeded
/// single-branch boundary Phase 6D introduces, not a full setup wizard.
class BranchAdminScreen extends ConsumerStatefulWidget {
  const BranchAdminScreen({
    super.key,
    this.authorizationPolicy,
    this.performedByStaffId = '',
  });

  final PosAuthorizationPolicy? authorizationPolicy;
  final String performedByStaffId;

  @override
  ConsumerState<BranchAdminScreen> createState() => _BranchAdminScreenState();
}

class _BranchAdminScreenState extends ConsumerState<BranchAdminScreen> {
  List<Branch>? _branches;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final branches = await ref.read(branchRepositoryProvider).findAll();
    if (!mounted) return;
    setState(() => _branches = branches);
  }

  Future<void> _setStatus(Branch branch, BranchStatus status) async {
    final policy = widget.authorizationPolicy;
    if (policy == null) {
      setState(() => _error = 'Yetki politikası tanımlı değil.');
      return;
    }
    try {
      await SetBranchStatus(
        authorizationPolicy: policy,
        repository: ref.read(branchRepositoryProvider),
        auditRepository: ref.read(adminAuditEntryRepositoryProvider),
      )(
        branchId: branch.id,
        newStatus: status,
        performedByStaffId: widget.performedByStaffId,
        performedAt: DateTime.now(),
      );
      setState(() => _error = null);
      await _load();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _toggleEmergencyStop(Branch branch) async {
    final policy = widget.authorizationPolicy;
    if (policy == null) {
      setState(() => _error = 'Yetki politikası tanımlı değil.');
      return;
    }
    try {
      await SetBranchEmergencyStop(
        authorizationPolicy: policy,
        repository: ref.read(branchRepositoryProvider),
        auditRepository: ref.read(adminAuditEntryRepositoryProvider),
      )(
        branchId: branch.id,
        stopped: !branch.emergencyStopped,
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
    final branches = _branches;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Şube Yönetimi'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: branches == null
            ? const LoadingView(message: 'Şubeler yükleniyor...')
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  if (_error != null) ...[
                    Text(_error!,
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.error)),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  for (final branch in branches)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: AppCard(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(branch.name,
                                    style: AppTypography.titleMedium),
                                if (branch.emergencyStopped)
                                  const Icon(Icons.warning_amber_rounded,
                                      color: AppColors.error),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'Durum: ${branch.status.name} · '
                              '${branch.timezone} · ${branch.currencyCode}',
                              style: AppTypography.bodySmall
                                  .copyWith(color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Wrap(
                              spacing: AppSpacing.sm,
                              children: [
                                if (branch.status != BranchStatus.active)
                                  OutlinedButton(
                                    onPressed: () =>
                                        _setStatus(branch, BranchStatus.active),
                                    child: const Text('Aktifleştir'),
                                  ),
                                if (branch.status == BranchStatus.active)
                                  OutlinedButton(
                                    onPressed: () => _setStatus(
                                        branch, BranchStatus.inactive),
                                    child: const Text('Pasifleştir'),
                                  ),
                                if (branch.status != BranchStatus.archived)
                                  OutlinedButton(
                                    onPressed: () => _setStatus(
                                        branch, BranchStatus.archived),
                                    child: const Text('Arşivle'),
                                  ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: branch.emergencyStopped
                                        ? AppColors.success
                                        : AppColors.error,
                                  ),
                                  onPressed: () => _toggleEmergencyStop(branch),
                                  child: Text(branch.emergencyStopped
                                      ? 'Acil Durdurmayı Kaldır'
                                      : 'Acil Durdur'),
                                ),
                              ],
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
