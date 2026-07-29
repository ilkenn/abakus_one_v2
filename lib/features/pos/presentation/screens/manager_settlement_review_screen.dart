import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/clock_provider.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../application/use_cases/approve_courier_settlement.dart';
import '../../application/use_cases/close_courier_settlement_session.dart';
import '../../application/use_cases/record_cash_movement.dart';
import '../../application/use_cases/reject_courier_settlement.dart';
import '../../domain/authorization/pos_authorization_policy.dart';
import '../../domain/courier_settlement/courier_cash_declaration.dart';
import '../../domain/courier_settlement/courier_settlement_session.dart';
import '../../domain/courier_settlement/courier_settlement_session_status.dart';
import '../../domain/courier_settlement/courier_settlement_variance.dart';
import '../providers/cash_dependencies_provider.dart';
import '../providers/courier_settlement_dependencies_provider.dart';

/// Manager Review of a courier's latest [CourierCashDeclaration] —
/// expected/declared/variance, Onayla/Reddet, and (once approved)
/// "Oturumu Kapat". Mirrors `CashReconciliationScreen`'s consolidation of
/// review + approval-action into one screen (Sprint 3E, ADR-014).
///
/// [authorizationPolicy] is nullable for the same reason
/// `CashReconciliationScreen`'s is: this screen must stay directly
/// navigable without every caller threading a real policy through
/// immediately — approve/reject actions check for one at call time.
class ManagerSettlementReviewScreen extends ConsumerStatefulWidget {
  const ManagerSettlementReviewScreen({
    super.key,
    required this.settlementSessionId,
    this.authorizationPolicy,
    this.reviewerStaffId = 'staff-2',
  });

  final String settlementSessionId;
  final PosAuthorizationPolicy? authorizationPolicy;
  final String reviewerStaffId;

  @override
  ConsumerState<ManagerSettlementReviewScreen> createState() =>
      _ManagerSettlementReviewScreenState();
}

class _ManagerSettlementReviewScreenState
    extends ConsumerState<ManagerSettlementReviewScreen> {
  CourierSettlementSession? _session;
  CourierCashDeclaration? _latestDeclaration;
  String? _message;
  final _targetCashSessionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _targetCashSessionController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final session = await ref
        .read(courierSettlementSessionRepositoryProvider)
        .findById(widget.settlementSessionId);
    final declaration = await ref
        .read(courierCashDeclarationRepositoryProvider)
        .findLatestBySettlementSessionId(widget.settlementSessionId);
    if (!mounted) return;
    setState(() {
      _session = session;
      _latestDeclaration = declaration;
    });
  }

  RecordCashMovement _buildRecordCashMovement() {
    return RecordCashMovement(
      clock: ref.read(clockProvider),
      idGenerator: ref.read(cashMovementIdGeneratorProvider),
      sessionRepository: ref.read(cashSessionRepositoryProvider),
      movementRepository: ref.read(cashMovementRepositoryProvider),
      auditRepository: ref.read(cashAuditEntryRepositoryProvider),
    );
  }

  Future<void> _approve({required bool acceptVariance}) async {
    final policy = widget.authorizationPolicy;
    if (policy == null) {
      setState(() => _message = 'Yetki politikası tanımlı değil.');
      return;
    }
    final targetCashSessionId = _targetCashSessionController.text.trim();
    if (targetCashSessionId.isEmpty) {
      setState(() => _message = 'Hedef kasa oturumu girin.');
      return;
    }
    try {
      await ApproveCourierSettlement(
        clock: ref.read(clockProvider),
        authorizationPolicy: policy,
        idGenerator: ref.read(courierSettlementIdGeneratorProvider),
        sessionRepository: ref.read(courierSettlementSessionRepositoryProvider),
        declarationRepository:
            ref.read(courierCashDeclarationRepositoryProvider),
        settlementRepository: ref.read(courierSettlementRepositoryProvider),
        auditRepository:
            ref.read(courierSettlementAuditEntryRepositoryProvider),
        recordCashMovement: _buildRecordCashMovement(),
      )(
        settlementSessionId: widget.settlementSessionId,
        reviewedByStaffId: widget.reviewerStaffId,
        targetCashSessionId: targetCashSessionId,
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
      await RejectCourierSettlement(
        clock: ref.read(clockProvider),
        authorizationPolicy: policy,
        idGenerator: ref.read(courierSettlementIdGeneratorProvider),
        sessionRepository: ref.read(courierSettlementSessionRepositoryProvider),
        declarationRepository:
            ref.read(courierCashDeclarationRepositoryProvider),
        settlementRepository: ref.read(courierSettlementRepositoryProvider),
        auditRepository:
            ref.read(courierSettlementAuditEntryRepositoryProvider),
      )(
        settlementSessionId: widget.settlementSessionId,
        reviewedByStaffId: widget.reviewerStaffId,
        managerNotes: 'Reddedildi',
      );
      setState(() => _message = null);
      await _load();
    } on BusinessRuleViolation catch (e) {
      setState(() => _message = e.description);
    }
  }

  Future<void> _closeSession() async {
    try {
      await CloseCourierSettlementSession(
        clock: ref.read(clockProvider),
        sessionRepository: ref.read(courierSettlementSessionRepositoryProvider),
        auditRepository:
            ref.read(courierSettlementAuditEntryRepositoryProvider),
      )(
        settlementSessionId: widget.settlementSessionId,
        closedByStaffId: widget.reviewerStaffId,
      );
      setState(() => _message = 'Kurye vardiyası kapatıldı.');
      await _load();
    } on BusinessRuleViolation catch (e) {
      setState(() => _message = e.description);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final declaration = _latestDeclaration;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Kurye Vardiyası İncelemesi'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: session == null || declaration == null
            ? const LoadingView(message: 'İnceleme yükleniyor...')
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
                          'Beklenen: ${(declaration.expectedAmount.minorUnits / 100).toStringAsFixed(2)}',
                        ),
                        Text(
                          'Bildirilen: ${(declaration.declaredAmount.minorUnits / 100).toStringAsFixed(2)}',
                        ),
                        Text(
                          'Fark: ${declaration.variance.type.name} '
                          '${(declaration.variance.amount.minorUnits / 100).toStringAsFixed(2)}',
                          style: TextStyle(
                            color: declaration.variance.type ==
                                    CourierVarianceType.exact
                                ? AppColors.success
                                : AppColors.warning,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (session.status ==
                      CourierSettlementSessionStatus.pendingApproval) ...[
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: _targetCashSessionController,
                      decoration: const InputDecoration(
                          labelText: 'Hedef Kasa Oturumu No'),
                    ),
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
                                acceptVariance: !declaration.variance.isExact),
                            child: const Text('Onayla'),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (session.status ==
                      CourierSettlementSessionStatus.approved) ...[
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
                ],
              ),
      ),
    );
  }
}
