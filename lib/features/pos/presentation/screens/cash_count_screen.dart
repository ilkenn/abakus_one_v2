import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/clock_provider.dart';
import '../../../../shared/models/currency.dart';
import '../../../../shared/models/money.dart';
import '../../application/use_cases/submit_cash_count.dart';
import '../providers/cash_dependencies_provider.dart';
import 'cash_reconciliation_screen.dart';

/// "Sayım Yap" — the cashier declares the physical cash actually present.
/// `SubmitCashCount` computes the expected figure and the resulting
/// variance authoritatively; this screen only collects the declaration.
class CashCountScreen extends ConsumerStatefulWidget {
  const CashCountScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<CashCountScreen> createState() => _CashCountScreenState();
}

class _CashCountScreenState extends ConsumerState<CashCountScreen> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  String? _error;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountController.text.replaceAll(',', '.'));
    if (amount == null) {
      setState(() => _error = 'Geçerli bir tutar girin');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await SubmitCashCount(
        clock: ref.read(clockProvider),
        idGenerator: ref.read(cashCountIdGeneratorProvider),
        sessionRepository: ref.read(cashSessionRepositoryProvider),
        movementRepository: ref.read(cashMovementRepositoryProvider),
        countRepository: ref.read(cashCountRepositoryProvider),
        auditRepository: ref.read(cashAuditEntryRepositoryProvider),
      )(
        sessionId: widget.sessionId,
        actualAmount: Money.fromLegacyDoubleTry(amount),
        notes: _notesController.text,
        declaredByStaffId: 'staff-1',
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => CashReconciliationScreen(sessionId: widget.sessionId),
      ));
    } on BusinessRuleViolation catch (e) {
      setState(() {
        _isSubmitting = false;
        _error = e.description;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Kasa Sayımı'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Kasadaki gerçek nakit tutarını girin',
                  style: AppTypography.bodyMedium),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText:
                        'Sayılan Tutar (${Currency.accountingCurrency.symbol})'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _notesController,
                decoration: const InputDecoration(labelText: 'Not'),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(_error!,
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.error)),
                ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child:
                      Text(_isSubmitting ? 'Gönderiliyor...' : 'Sayımı Gönder'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
