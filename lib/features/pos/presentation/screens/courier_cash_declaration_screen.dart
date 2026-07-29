import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/clock_provider.dart';
import '../../../../shared/models/currency.dart';
import '../../../../shared/models/money.dart';
import '../../application/use_cases/submit_courier_cash_declaration.dart';
import '../providers/courier_settlement_dependencies_provider.dart';

/// "Kasayı Bildir" — the courier declares the total cash they are
/// physically holding at the end of the shift. `SubmitCourierCashDeclaration`
/// computes the expected figure and the resulting variance authoritatively;
/// this screen only collects the declaration. Mirrors `CashCountScreen`
/// (Sprint 3E).
class CourierCashDeclarationScreen extends ConsumerStatefulWidget {
  const CourierCashDeclarationScreen(
      {super.key, required this.settlementSessionId});

  final String settlementSessionId;

  @override
  ConsumerState<CourierCashDeclarationScreen> createState() =>
      _CourierCashDeclarationScreenState();
}

class _CourierCashDeclarationScreenState
    extends ConsumerState<CourierCashDeclarationScreen> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  String? _error;
  bool _isSubmitting = false;
  bool _submitted = false;

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
      await SubmitCourierCashDeclaration(
        clock: ref.read(clockProvider),
        idGenerator: ref.read(courierCashDeclarationIdGeneratorProvider),
        sessionRepository: ref.read(courierSettlementSessionRepositoryProvider),
        collectionRepository: ref.read(courierCashCollectionRepositoryProvider),
        declarationRepository:
            ref.read(courierCashDeclarationRepositoryProvider),
        auditRepository:
            ref.read(courierSettlementAuditEntryRepositoryProvider),
      )(
        settlementSessionId: widget.settlementSessionId,
        declaredAmount: Money.fromLegacyDoubleTry(amount),
        notes: _notesController.text,
      );
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitted = true;
      });
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
        title: const Text('Kasa Bildirimi'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: _submitted
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                        'Bildirim gönderildi. Yönetici onayı bekleniyor.',
                        style: AppTypography.bodyLarge),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Geri Dön'),
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Elinizdeki toplam nakit tutarı girin',
                        style: AppTypography.bodyMedium),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: _amountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText:
                              'Bildirilen Tutar (${Currency.accountingCurrency.symbol})'),
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
                        child: Text(_isSubmitting
                            ? 'Gönderiliyor...'
                            : 'Bildirimi Gönder'),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
