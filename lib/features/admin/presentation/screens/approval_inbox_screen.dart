import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../navigation/presentation/providers/current_branch_provider.dart';
import '../../../pos/domain/authorization/staff_role.dart';
import '../../../pos/presentation/providers/actor_session_provider.dart';
import '../../data/approval_gateway.dart';
import '../../domain/approval/approval_request.dart';
import '../providers/admin_dependencies_provider.dart';

const _statusLabels = {
  ApprovalStatus.pending: 'Bekliyor',
  ApprovalStatus.approved: 'Onaylandı',
  ApprovalStatus.rejected: 'Reddedildi',
  ApprovalStatus.expired: 'Süresi Doldu',
  ApprovalStatus.escalated: 'Yükseltildi',
  ApprovalStatus.cancelled: 'İptal Edildi',
};

const _actionTypeLabels = {
  ApprovalActionType.deviceActivation: 'Cihaz Aktivasyonu',
  ApprovalActionType.checkFinancialAdjustment: 'Fiyat Düzeltmesi',
  ApprovalActionType.acceptedLineCancellation: 'Kabul Edilen Ürün İptali',
  ApprovalActionType.boncukBalanceCorrection: 'Boncuk Bakiye Düzeltmesi',
};

const _eligibleResponderRoles = {
  StaffRole.manager,
  StaffRole.admin,
  StaffRole.tenantOwner,
};

/// AP-2 final wiring — the real Remote Approval Inbox. Reachable from the
/// Admin shell header (`_TopBar`'s bell icon, `admin_shell_screen.dart`)
/// and from the Trusted Devices tab's "Onay Kutusuna Git" shortcut —
/// deliberately NOT one of `AdminShellScreen`'s 31 registered nav-item
/// destinations, so it is never wrapped by `ModuleReadinessGate` (a
/// header-launched screen structurally bypasses that per-destination
/// gate) — appropriate here because this screen genuinely IS real,
/// backend-wired, and requires no readiness gating of its own.
class ApprovalInboxScreen extends ConsumerStatefulWidget {
  const ApprovalInboxScreen({super.key});

  @override
  ConsumerState<ApprovalInboxScreen> createState() =>
      _ApprovalInboxScreenState();
}

class _ApprovalInboxScreenState extends ConsumerState<ApprovalInboxScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(actorSessionProvider);
    final isEligibleResponder =
        session != null && session.roles.any(_eligibleResponderRoles.contains);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Onay Kutusu'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Bekleyen Onaylar'),
            Tab(text: 'Taleplerim'),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            if (isEligibleResponder)
              const _EligibleApprovalsTab()
            else
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    'Onay verme yetkiniz yok — yalnız yönetici ve üzeri '
                    'roller bekleyen talepleri onaylayabilir/reddedebilir.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            _MyRequestsTab(actorUid: session?.actorId),
          ],
        ),
      ),
    );
  }
}

class _EligibleApprovalsTab extends ConsumerWidget {
  const _EligibleApprovalsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final organizationId = ref.watch(currentOrganizationIdProvider);
    final branchId = ref.watch(currentBranchIdProvider);
    final scope = (organizationId: organizationId, branchId: branchId);
    final requestsAsync = ref.watch(_eligibleApprovalsProvider(scope));

    return requestsAsync.when(
      loading: () => const LoadingView(message: 'Onay talepleri yükleniyor...'),
      error: (error, stackTrace) => ErrorView(
        message: 'Onay backend\'ine ulaşılamadı.',
        retryLabel: 'Tekrar Dene',
        onRetry: () => ref.invalidate(_eligibleApprovalsProvider(scope)),
      ),
      data: (requests) {
        if (requests.isEmpty) {
          return const EmptyView(
            icon: Icons.inbox_outlined,
            message: 'Bekleyen ya da geçmiş onay talebi yok.',
          );
        }
        final actorId = ref.watch(actorSessionProvider)?.actorId;
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            for (final request in requests)
              _ApprovalCard(
                request: request,
                isSelfRequest: request.requestedByActorUid == actorId,
              ),
          ],
        );
      },
    );
  }
}

class _ApprovalCard extends ConsumerStatefulWidget {
  const _ApprovalCard({required this.request, required this.isSelfRequest});

  final ApprovalRequest request;
  final bool isSelfRequest;

  @override
  ConsumerState<_ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends ConsumerState<_ApprovalCard> {
  bool _submitting = false;

  Future<void> _respond(bool approve) async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approve ? 'Talebi Onayla' : 'Talebi Reddet'),
        content: TextField(
          controller: reasonController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Gerekçe (zorunlu)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            // Not disabled based on live text — see `device_registry_screen
            // .dart`'s identical fix/comment for why a plain `TextField`
            // inside this non-`StatefulBuilder` dialog can never re-enable
            // a conditionally-disabled button. Blank input is rejected
            // right after the dialog closes instead.
            onPressed: () =>
                Navigator.of(context).pop(reasonController.text.trim()),
            child: Text(approve ? 'Onayla' : 'Reddet'),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty || _submitting) return;

    setState(() => _submitting = true);
    try {
      await ref.read(approvalGatewayProvider).respond(
            requestId: widget.request.requestId,
            approve: approve,
            reasonMessage: reason,
          );
    } on ApprovalException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '${_actionTypeLabels[request.actionType]} · '
                    '${request.targetDeviceId.length > 8 ? "${request.targetDeviceId.substring(0, 8)}…" : request.targetDeviceId}',
                    style: AppTypography.titleMedium,
                  ),
                ),
                _StatusChip(status: request.status),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Talep eden: ${request.requestedByActorUid} · '
              'Oluşturulma: ${request.createdAt}',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
            Text(
              'Son geçerlilik: ${request.expiresAt}'
              '${request.escalatedTo != null ? " · Yükseltildi: ${request.escalatedTo}" : ""}',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
            if (widget.isSelfRequest)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  'Bu talebi siz oluşturdunuz — kendi talebinizi '
                  'onaylayamaz/reddedemezsiniz.',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.warning),
                ),
              ),
            if (request.isRespondable && !widget.isSelfRequest) ...[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  ElevatedButton(
                    onPressed: _submitting ? null : () => _respond(true),
                    child: const Text('Onayla'),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error),
                    onPressed: _submitting ? null : () => _respond(false),
                    child: const Text('Reddet'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MyRequestsTab extends ConsumerWidget {
  const _MyRequestsTab({required this.actorUid});

  final String? actorUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = actorUid;
    if (uid == null) {
      return const Center(child: Text('Oturum bulunamadı.'));
    }
    final requestsAsync = ref.watch(_myRequestsProvider(uid));

    return requestsAsync.when(
      loading: () => const LoadingView(message: 'Talepleriniz yükleniyor...'),
      error: (error, stackTrace) => ErrorView(
        message: 'Onay backend\'ine ulaşılamadı.',
        retryLabel: 'Tekrar Dene',
        onRetry: () => ref.invalidate(_myRequestsProvider(uid)),
      ),
      data: (requests) {
        if (requests.isEmpty) {
          return const EmptyView(
            icon: Icons.history_outlined,
            message: 'Oluşturduğunuz bir onay talebi yok.',
          );
        }
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            for (final request in requests)
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
                          Expanded(
                            child: Text(
                              _actionTypeLabels[request.actionType]!,
                              style: AppTypography.titleMedium,
                            ),
                          ),
                          _StatusChip(status: request.status),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        request.status == ApprovalStatus.approved
                            ? 'Talebiniz onaylandı — cihaz artık aktif.'
                            : 'Oluşturulma: ${request.createdAt}',
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final ApprovalStatus status;

  Color _colorFor(ApprovalStatus status) {
    switch (status) {
      case ApprovalStatus.approved:
        return AppColors.success;
      case ApprovalStatus.pending:
        return AppColors.warning;
      case ApprovalStatus.escalated:
        return AppColors.warning;
      case ApprovalStatus.rejected:
      case ApprovalStatus.expired:
      case ApprovalStatus.cancelled:
        return AppColors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(status);
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _statusLabels[status]!,
        style: AppTypography.labelMedium.copyWith(color: color),
      ),
    );
  }
}

final _eligibleApprovalsProvider = StreamProvider.family<List<ApprovalRequest>,
    ({String organizationId, String branchId})>((ref, scope) {
  return ref.watch(approvalRepositoryProvider).watchEligibleApprovals(
        organizationId: scope.organizationId,
        branchId: scope.branchId,
      );
});

final _myRequestsProvider =
    StreamProvider.family<List<ApprovalRequest>, String>((ref, actorUid) {
  return ref
      .watch(approvalRepositoryProvider)
      .watchMyRequests(actorUid: actorUid);
});
