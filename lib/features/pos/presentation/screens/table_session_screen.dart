import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/clock_provider.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../orders/presentation/providers/order_identity_provider.dart';
import '../../../qr/presentation/providers/table_session_dependencies_provider.dart';
import '../../application/use_cases/cancel_check.dart';
import '../../application/use_cases/close_table_session.dart';
import '../../application/use_cases/open_check.dart';
import '../../application/use_cases/submit_check.dart';
import '../../domain/models/check.dart';
import '../../domain/models/check_status.dart';
import '../providers/check_dependencies_provider.dart';
import '../providers/order_closure_dependencies_provider.dart';
import '../providers/pos_dependencies_provider.dart';

/// Lists every [Check] under one [TableSession], with lifecycle actions
/// (open a new check, submit, cancel, close the table session once every
/// check is resolved).
///
/// Deliberately does not embed cart/item-editing UI — opening a check
/// starts its `PosOrderSession` draft, but adding products to it is
/// `PosCashierScreen`'s job; wiring the two together (so "edit this
/// check's items" pushes into a cashier flow scoped to one already-started
/// session) is flagged as follow-up integration work, not built this
/// sprint (`docs/decisions.md` ADR-013) — `PosCashierScreen` only knows
/// how to start its own session today.
class TableSessionScreen extends ConsumerStatefulWidget {
  const TableSessionScreen({
    super.key,
    required this.tableSessionId,
    required this.restaurantId,
    required this.staffId,
  });

  final String tableSessionId;
  final String restaurantId;
  final String staffId;

  @override
  ConsumerState<TableSessionScreen> createState() => _TableSessionScreenState();
}

class _TableSessionScreenState extends ConsumerState<TableSessionScreen> {
  List<Check>? _checks;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final checks = await ref
        .read(checkRepositoryProvider)
        .findByTableSessionId(widget.tableSessionId);
    if (!mounted) return;
    setState(() => _checks = checks);
  }

  Future<void> _openCheck() async {
    final useCase = OpenCheck(
      clock: ref.read(clockProvider),
      idGenerator: ref.read(checkIdGeneratorProvider),
      tableSessionRepository: ref.read(tableSessionRepositoryProvider),
      posOrderRepository: ref.read(posOrderRepositoryProvider),
      checkRepository: ref.read(checkRepositoryProvider),
    );
    await useCase(
      tableSessionId: widget.tableSessionId,
      openedByStaffId: widget.staffId,
    );
    await _load();
  }

  Future<void> _submitCheck(Check check) async {
    final useCase = SubmitCheck(
      clock: ref.read(clockProvider),
      identityProvider: ref.read(orderIdentityProvider),
      restaurantId: widget.restaurantId,
      checkRepository: ref.read(checkRepositoryProvider),
      posOrderRepository: ref.read(posOrderRepositoryProvider),
      tableSessionRepository: ref.read(tableSessionRepositoryProvider),
    );
    try {
      await useCase(check);
      setState(() => _message = null);
    } on BusinessRuleViolation catch (e) {
      setState(() => _message = e.description);
    }
    await _load();
  }

  Future<void> _cancelCheck(Check check) async {
    final useCase = CancelCheck(
      checkRepository: ref.read(checkRepositoryProvider),
      posOrderRepository: ref.read(posOrderRepositoryProvider),
    );
    await useCase(check);
    await _load();
  }

  Future<void> _closeTableSession() async {
    final useCase = CloseTableSession(
      clock: ref.read(clockProvider),
      tableSessionRepository: ref.read(tableSessionRepositoryProvider),
      checkRepository: ref.read(checkRepositoryProvider),
      orderClosureRepository: ref.read(orderClosureRepositoryProvider),
    );
    try {
      await useCase(widget.tableSessionId);
      setState(() => _message = 'Masa oturumu kapatıldı.');
    } on BusinessRuleViolation catch (e) {
      setState(() => _message = e.description);
    }
  }

  @override
  Widget build(BuildContext context) {
    final checks = _checks;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Masa Oturumu'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Yeni Adisyon Aç',
            onPressed: _openCheck,
          ),
        ],
      ),
      body: SafeArea(
        child: checks == null
            ? const LoadingView(message: 'Adisyonlar yükleniyor...')
            : Column(
                children: [
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      itemCount: checks.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, index) {
                        final check = checks[index];
                        return AppCard(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(check.id,
                                        style: AppTypography.bodyLarge),
                                    Text(check.status.name,
                                        style: AppTypography.bodySmall.copyWith(
                                            color: AppColors.textSecondary)),
                                  ],
                                ),
                              ),
                              if (check.status == CheckStatus.open) ...[
                                TextButton(
                                  onPressed: () => _cancelCheck(check),
                                  child: const Text('İptal Et'),
                                ),
                                ElevatedButton(
                                  onPressed: () => _submitCheck(check),
                                  child: const Text('Gönder'),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      children: [
                        if (_message != null)
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.sm),
                            child:
                                Text(_message!, style: AppTypography.bodySmall),
                          ),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _closeTableSession,
                            child: const Text('Masayı Kapat'),
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
