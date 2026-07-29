import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/clock_provider.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../application/use_cases/approve_cash_reconciliation.dart';
import '../../application/use_cases/close_cash_session.dart';
import '../../application/use_cases/reject_cash_reconciliation.dart';
import '../../domain/authorization/pos_authorization_policy.dart';
import '../../domain/cash/cash_count.dart';
import '../../domain/cash/cash_reconciliation.dart';
import '../../domain/cash/cash_session.dart';
import '../../domain/cash/cash_session_status.dart';
import '../../domain/cash/cash_variance.dart';
import '../providers/cash_dependencies_provider.dart';

/// Combines "Reconciliation Screen" and "Manager Approval Screen" into
/// one view: the latest [CashCount]'s expected/actual/variance, every
/// past [CashReconciliation] (approved and rejected alike, per the
/// append-only requirement), and — while the session is
/// [CashSessionStatus.pendingApproval] — the approve/reject actions
/// themselves. A deliberate consolidation, the same kind Sprint 3D's
/// `ClosedAccountDetailScreen` already made for its own view+actions.
///
/// [authorizationPolicy] is a required constructor parameter, never a
/// Riverpod-provider default — mirrors `ClosedAccountsScreen`'s
/// precedent exactly (`PosAuthorizationPolicy` has no production
/// implementation by design).
class CashReconciliationScreen extends ConsumerStatefulWidget {
  const CashReconciliationScreen({
    super.key,
    required this.sessionId,
    this.authorizationPolicy,
    this.viewerStaffId = 'staff-2',
  });

  final String sessionId;

  /// Nullable so this screen remains directly navigable from
  /// `CashCountScreen` without every caller having to thread a real
  /// policy through immediately — approve/reject actions check for one
  /// at call time and surface a clear message if absent, rather than the
  /// screen refusing to build at all.
  final PosAuthorizationPolicy? authorizationPolicy;
  final String viewerStaffId;

  @override
  ConsumerState<CashReconciliationScreen> createState() =>
      _CashReconciliationScreenState();
}

class _CashReconciliationScreenState
    extends ConsumerState<CashReconciliationScreen> {
  CashSession? _session;
  CashCount? _latestCount;
  List<CashReconciliation>? _history;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final session = await ref
        .read(cashSessionRepositoryProvider)
        .findById(widget.sessionId);
    final latestCount = await ref
        .read(cashCountRepositoryProvider)
        .findLatestBySessionId(widget.sessionId);
    final history = await ref
        .read(cashReconciliationRepositoryProvider)
        .findBySessionId(widget.sessionId);
    if (!mounted) return;
    setState(() {
      _session = session;
      _latestCount = latestCount;
      _history = history;
    });
  }

  Future<void> _approve({required bool acceptVariance}) async {
    final policy = widget.authorizationPolicy;
    if (policy == null) {
      setState(() => _message = 'Yetki politikası tanımlı değil.');
      return;
    }
    try {
      await ApproveCashReconciliation(
        clock: ref.read(clockProvider),
        authorizationPolicy: policy,
        idGenerator: ref.read(cashReconciliationIdGeneratorProvider),
        sessionRepository: ref.read(cashSessionRepositoryProvider),
        countRepository: ref.read(cashCountRepositoryProvider),
        reconciliationRepository:
            ref.read(cashReconciliationRepositoryProvider),
        auditRepository: ref.read(cashAuditEntryRepositoryProvider),
      )(
        sessionId: widget.sessionId,
        reviewedByStaffId: widget.viewerStaffId,
        varianceAccepted: acceptVariance,
      );
      setState(() => _message = null);
      await _load();
    } on BusinessRuleViolation catch (e) {
      setState(() => _message = e.description);
    }
  }

  Future<void> _reject() async {
    final policy = widget.authorizationPolicy;
    if (policy == null) {
      setState(() => _message = 'Yetki politikası tanımlı değil.');
      return;
    }
    try {
      await RejectCashReconciliation(
        clock: ref.read(clockProvider),
        authorizationPolicy: policy,
        idGenerator: ref.read(cashReconciliationIdGeneratorProvider),
        sessionRepository: ref.read(cashSessionRepositoryProvider),
        countRepository: ref.read(cashCountRepositoryProvider),
        reconciliationRepository:
            ref.read(cashReconciliationRepositoryProvider),
        auditRepository: ref.read(cashAuditEntryRepositoryProvider),
      )(
        sessionId: widget.sessionId,
        reviewedByStaffId: widget.viewerStaffId,
        managerComments: 'Reddedildi',
      );
      setState(() => _message = null);
      await _load();
    } on BusinessRuleViolation catch (e) {
      setState(() => _message = e.description);
    }
  }

  Future<void> _closeSession() async {
    try {
      await CloseCashSession(
        clock: ref.read(clockProvider),
        sessionRepository: ref.read(cashSessionRepositoryProvider),
        reconciliationRepository:
            ref.read(cashReconciliationRepositoryProvider),
        auditRepository: ref.read(cashAuditEntryRepositoryProvider),
      )(sessionId: widget.sessionId, closedByStaffId: widget.viewerStaffId);
      setState(() => _message = 'Kasa oturumu kapatıldı.');
      await _load();
    } on BusinessRuleViolation catch (e) {
      setState(() => _message = e.description);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final count = _latestCount;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Kasa Mutabakatı'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: session == null || count == null
            ? const LoadingView(message: 'Mutabakat yükleniyor...')
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  AppCard(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Durum: ${session.status.name}',
                            style: AppTypography.bodyLarge),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Beklenen: ${(count.expectedAmount.minorUnits / 100).toStringAsFixed(2)}',
                        ),
                        Text(
                          'Sayılan: ${(count.declaration.actualAmount.minorUnits / 100).toStringAsFixed(2)}',
                        ),
                        Text(
                          'Fark: ${count.variance.type.name} '
                          '${(count.variance.amount.minorUnits / 100).toStringAsFixed(2)}',
                          style: TextStyle(
                            color: count.variance.type == CashVarianceType.exact
                                ? AppColors.success
                                : AppColors.warning,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (session.status == CashSessionStatus.pendingApproval) ...[
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _reject,
                            child: const Text('Reddet'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _approve(
                                acceptVariance: !count.variance.isExact),
                            child: const Text('Onayla'),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (session.status == CashSessionStatus.approved) ...[
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _closeSession,
                        child: const Text('Oturumu Kapat'),
                      ),
                    ),
                  ],
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Text(_message!, style: AppTypography.bodySmall),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  const Text('Geçmiş', style: AppTypography.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  for (final entry in _history ?? const <CashReconciliation>[])
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: Text(
                        '${entry.status.name} • ${entry.reviewedByStaffId} • ${entry.managerComments}',
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
