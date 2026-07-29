import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/clock_provider.dart';
import '../../../../shared/models/currency.dart';
import '../../../../shared/models/money.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../application/use_cases/record_cash_movement.dart';
import '../../domain/cash/cash_movement.dart';
import '../../domain/cash/cash_movement_type.dart';
import '../../domain/cash/cash_session.dart';
import '../providers/cash_dependencies_provider.dart';
import 'cash_count_screen.dart';

/// The current, active [CashSession] view — every recorded
/// [CashMovement], plus actions to add one and to move on to counting.
class CashSessionScreen extends ConsumerStatefulWidget {
  const CashSessionScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<CashSessionScreen> createState() => _CashSessionScreenState();
}

class _CashSessionScreenState extends ConsumerState<CashSessionScreen> {
  CashSession? _session;
  List<CashMovement>? _movements;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final session = await ref
        .read(cashSessionRepositoryProvider)
        .findById(widget.sessionId);
    final movements = await ref
        .read(cashMovementRepositoryProvider)
        .findBySessionId(widget.sessionId);
    if (!mounted) return;
    setState(() {
      _session = session;
      _movements = movements;
    });
  }

  Future<void> _addMovement() async {
    final result = await showDialog<
        ({CashMovementType type, double amount, String reason})>(
      context: context,
      builder: (context) => const _AddMovementDialog(),
    );
    if (result == null) return;

    await RecordCashMovement(
      clock: ref.read(clockProvider),
      idGenerator: ref.read(cashMovementIdGeneratorProvider),
      sessionRepository: ref.read(cashSessionRepositoryProvider),
      movementRepository: ref.read(cashMovementRepositoryProvider),
      auditRepository: ref.read(cashAuditEntryRepositoryProvider),
    )(
      sessionId: widget.sessionId,
      type: result.type,
      amount: Money.fromLegacyDoubleTry(result.amount),
      reason: result.reason,
      actorStaffId: 'staff-1',
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final movements = _movements;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Kasa Oturumu'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Hareket Ekle',
            onPressed: _addMovement,
          ),
        ],
      ),
      body: SafeArea(
        child: movements == null
            ? const LoadingView(message: 'Hareketler yükleniyor...')
            : Column(
                children: [
                  if (_session != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Durum: ${_session!.status.name}',
                            style: AppTypography.bodySmall
                                .copyWith(color: AppColors.textSecondary)),
                      ),
                    ),
                  Expanded(
                    child: movements.isEmpty
                        ? const EmptyView(
                            icon: Icons.receipt_long_outlined,
                            message: 'Henüz kasa hareketi yok',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            itemCount: movements.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: AppSpacing.sm),
                            itemBuilder: (context, index) {
                              final movement = movements[index];
                              return AppCard(
                                padding: const EdgeInsets.all(AppSpacing.sm),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Flexible(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(movement.type.name,
                                              style: AppTypography.bodyMedium),
                                          Text(movement.reason,
                                              style: AppTypography.bodySmall
                                                  .copyWith(
                                                      color: AppColors
                                                          .textSecondary)),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      (movement.amount.minorUnits / 100)
                                          .toStringAsFixed(2),
                                      style: AppTypography.bodyMedium.copyWith(
                                        color: movement.amount.isNegative
                                            ? AppColors.error
                                            : AppColors.success,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) =>
                                CashCountScreen(sessionId: widget.sessionId),
                          ));
                        },
                        child: const Text('Sayım Yap'),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _AddMovementDialog extends StatefulWidget {
  const _AddMovementDialog();

  @override
  State<_AddMovementDialog> createState() => _AddMovementDialogState();
}

class _AddMovementDialogState extends State<_AddMovementDialog> {
  CashMovementType _type = CashMovementType.cashSale;
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Kasa Hareketi Ekle'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButton<CashMovementType>(
            value: _type,
            isExpanded: true,
            items: [
              for (final type in CashMovementType.values)
                DropdownMenuItem(value: type, child: Text(type.name)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _type = value);
            },
          ),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                labelText: 'Tutar (${Currency.accountingCurrency.symbol})'),
          ),
          TextField(
            controller: _reasonController,
            decoration: const InputDecoration(labelText: 'Açıklama'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          onPressed: () {
            final amount =
                double.tryParse(_amountController.text.replaceAll(',', '.'));
            if (amount == null) return;
            Navigator.of(context).pop((
              type: _type,
              amount: amount,
              reason: _reasonController.text,
            ));
          },
          child: const Text('Ekle'),
        ),
      ],
    );
  }
}
