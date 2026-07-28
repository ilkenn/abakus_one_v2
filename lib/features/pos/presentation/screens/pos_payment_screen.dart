import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/layout/app_breakpoints.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/money.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../../shared/widgets/images/payment_method_logo.dart';
import '../../../../shared/widgets/layout/app_section_header.dart';
import '../../../orders/domain/models/order.dart';
import '../../../payment/domain/models/payment_method.dart';
import '../../../payment/domain/models/payment_method_reporting_category.dart';
import '../../../payment/domain/models/payment_method_seed_data.dart';
import '../../domain/models/payment_session.dart';
import '../../domain/models/payment_session_status.dart';
import '../providers/payment_session_provider.dart';

/// The payment-collection screen for an already-submitted [Order] —
/// per the approved architecture, this screen only ever opens once
/// `SubmitPosOrder` has produced a real `Order`/`OrderId`
/// (`docs/decisions.md` ADR-012). Standalone/directly constructible for
/// tests, matching `PosCashierScreen`'s own precedent.
class PosPaymentScreen extends ConsumerStatefulWidget {
  const PosPaymentScreen({
    super.key,
    required this.sessionId,
    required this.order,
  });

  final String sessionId;
  final Order order;

  @override
  ConsumerState<PosPaymentScreen> createState() => _PosPaymentScreenState();
}

class _PosPaymentScreenState extends ConsumerState<PosPaymentScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startSession());
  }

  void _startSession() {
    ref.read(paymentSessionProvider.notifier).startSession(
          sessionId: widget.sessionId,
          orderId: widget.order.id,
          totalAmount: widget.order.pricing.grandTotal,
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(paymentSessionProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Ödeme'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: state.isIdle
            ? const LoadingView(message: 'Ödeme oturumu başlatılıyor...')
            : state.session!.status == PaymentSessionStatus.completed
                ? _PaymentCompletedView(session: state.session!)
                : _PaymentEditingLayout(order: widget.order, session: state.session!),
      ),
    );
  }
}

class _PaymentCompletedView extends StatelessWidget {
  const _PaymentCompletedView({required this.session});

  final PaymentSession session;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 72),
            const SizedBox(height: AppSpacing.md),
            const Text('Ödeme Tamamlandı', style: AppTypography.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${session.totalSettled}',
              style: AppTypography.bodyLarge.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentEditingLayout extends StatelessWidget {
  const _PaymentEditingLayout({required this.order, required this.session});

  final Order order;
  final PaymentSession session;

  @override
  Widget build(BuildContext context) {
    final summaryPanel = _OrderSummaryPanel(order: order, session: session);
    final collectionPanel = _PaymentCollectionPanel(session: session);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= AppBreakpoints.tablet;
        if (isWide) {
          return Row(
            children: [
              Expanded(flex: 2, child: summaryPanel),
              const VerticalDivider(width: 1, color: AppColors.border),
              Expanded(flex: 3, child: collectionPanel),
            ],
          );
        }
        return Column(
          children: [
            summaryPanel,
            const Divider(height: 1, color: AppColors.border),
            Expanded(child: collectionPanel),
          ],
        );
      },
    );
  }
}

/// Read-only order context + the three always-visible figures (Tahsil
/// Edilen / Kalan / Para Üstü), updated live from [session].
class _OrderSummaryPanel extends StatelessWidget {
  const _OrderSummaryPanel({required this.order, required this.session});

  final Order order;
  final PaymentSession session;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(title: 'Sipariş ${order.orderNumber.value}'),
          const SizedBox(height: AppSpacing.sm),
          for (final line in order.lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '${line.quantity}x ${line.productName}',
                      style: AppTypography.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text('${line.lineTotal}', style: AppTypography.bodyMedium),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          _AmountHighlightCard(session: session),
        ],
      ),
    );
  }
}

/// Tahsil Edilen / Kalan / Para Üstü — the most prominent element on this
/// screen, per the approved requirement. Real-time: rebuilds whenever
/// [session] changes.
class _AmountHighlightCard extends StatelessWidget {
  const _AmountHighlightCard({required this.session});

  final PaymentSession session;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      borderColor: AppColors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HighlightRow(label: 'Toplam', amount: session.totalAmount),
          const Divider(color: AppColors.border),
          _HighlightRow(label: 'Tahsil Edilen', amount: session.totalSettled),
          _HighlightRow(
            label: 'Kalan',
            amount: session.remainingAmount,
            emphasize: true,
          ),
          if (session.changeAmount.isPositive)
            _HighlightRow(
              label: 'Para Üstü',
              amount: session.changeAmount,
              emphasize: true,
              color: AppColors.success,
            ),
        ],
      ),
    );
  }
}

class _HighlightRow extends StatelessWidget {
  const _HighlightRow({
    required this.label,
    required this.amount,
    this.emphasize = false,
    this.color,
  });

  final String label;
  final Money amount;
  final bool emphasize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = (emphasize ? AppTypography.titleMedium : AppTypography.bodyMedium)
        .copyWith(color: color ?? (emphasize ? AppColors.textPrimary : AppColors.textSecondary));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(label, style: style, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text('$amount', style: style),
        ],
      ),
    );
  }
}

enum _CashEntryMode { collectAmount, tenderedAmount }

class _PaymentCollectionPanel extends ConsumerStatefulWidget {
  const _PaymentCollectionPanel({required this.session});

  final PaymentSession session;

  @override
  ConsumerState<_PaymentCollectionPanel> createState() => _PaymentCollectionPanelState();
}

class _PaymentCollectionPanelState extends ConsumerState<_PaymentCollectionPanel> {
  PaymentMethod _selectedMethod = PaymentMethodSeedData.cash;
  _CashEntryMode _cashEntryMode = _CashEntryMode.collectAmount;
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  bool get _isCash =>
      _selectedMethod.reportingCategory == PaymentMethodReportingCategory.cash;

  Future<void> _openCalculator() async {
    final result = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _CalculatorSheet(),
    );
    if (result != null) {
      _amountController.text = result.toStringAsFixed(2);
    }
  }

  void _fillRemaining() {
    final remaining = widget.session.remainingAmount;
    final whole = remaining.minorUnits / remaining.currency.minorUnitsPerWhole;
    _amountController.text = whole.toStringAsFixed(2);
  }

  Future<void> _addSplit() async {
    final parsed = double.tryParse(_amountController.text.replaceAll(',', '.'));
    if (parsed == null || parsed <= 0) return;
    final amount = Money.fromLegacyDoubleTry(parsed);
    final reference =
        _referenceController.text.trim().isEmpty ? null : _referenceController.text.trim();

    await ref.read(paymentSessionProvider.notifier).addSplit(
          method: _selectedMethod,
          amount: amount,
          transactionReference: reference,
        );
    _amountController.clear();
    _referenceController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final notifier = ref.read(paymentSessionProvider.notifier);
    final state = ref.watch(paymentSessionProvider);
    final isBusy = state.isCompleting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSectionHeader(title: 'Ödeme Yöntemi'),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final method in PaymentMethodSeedData.active)
                      _PaymentMethodCard(
                        method: method,
                        isSelected: method == _selectedMethod,
                        onTap: () => setState(() => _selectedMethod = method),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (_isCash)
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Tahsil Edilecek Tutar'),
                          selected: _cashEntryMode == _CashEntryMode.collectAmount,
                          onSelected: (_) =>
                              setState(() => _cashEntryMode = _CashEntryMode.collectAmount),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Müşterinin Verdiği Nakit'),
                          selected: _cashEntryMode == _CashEntryMode.tenderedAmount,
                          onSelected: (_) =>
                              setState(() => _cashEntryMode = _CashEntryMode.tenderedAmount),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: _isCash && _cashEntryMode == _CashEntryMode.tenderedAmount
                              ? 'Müşterinin Verdiği Nakit'
                              : 'Tutar',
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.calculate_outlined),
                      tooltip: 'Hesap Makinesi',
                      onPressed: _openCalculator,
                    ),
                  ],
                ),
                if (_isCash && _cashEntryMode == _CashEntryMode.collectAmount)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _fillRemaining,
                      child: const Text('Kalanı Doldur'),
                    ),
                  ),
                if (_selectedMethod.requiresReferenceNumber)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: TextField(
                      controller: _referenceController,
                      decoration: const InputDecoration(labelText: 'Referans Numarası'),
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: isBusy ? null : _addSplit,
                    child: const Text('Ekle'),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                const AppSectionHeader(title: 'Ödeme Satırları'),
                const SizedBox(height: AppSpacing.sm),
                if (session.splits.isEmpty)
                  Text(
                    'Henüz ödeme eklenmedi',
                    style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
                  )
                else
                  for (final split in session.splits)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: AppCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        child: Row(
                          children: [
                            PaymentMethodLogo(
                              iconAssetPath: split.methodSnapshot.iconAssetPath,
                              brandColorValue: split.methodSnapshot.brandColorValue,
                              size: 28,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                '${split.methodSnapshot.displayName} — ${split.amount}',
                                style: AppTypography.bodyMedium,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: AppColors.error),
                              onPressed: isBusy
                                  ? null
                                  : () => notifier.removeSplit(split.id),
                            ),
                          ],
                        ),
                      ),
                    ),
                if (state.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: ErrorView(message: state.error!.description),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isBusy ? null : notifier.cancel,
                  child: const Text('Ödemeyi İptal Et'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: isBusy || session.status != PaymentSessionStatus.readyToComplete
                      ? null
                      : () => notifier.complete(),
                  child: isBusy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.onPrimary,
                          ),
                        )
                      : const Text('Ödemeyi Tamamla'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PaymentMethodCard extends StatelessWidget {
  const _PaymentMethodCard({
    required this.method,
    required this.isSelected,
    required this.onTap,
  });

  final PaymentMethod method;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: AppRadius.kMedium,
      onTap: onTap,
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.sm),
        borderColor: isSelected ? AppColors.primary : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PaymentMethodLogo(
              iconAssetPath: method.iconAssetPath,
              brandColorValue: method.brandColorValue,
              size: 36,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(method.name, style: AppTypography.bodySmall, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// A simple sequential calculator (each operator applies immediately to
/// the running total, like a physical calculator — not a full expression
/// parser). Never touches the payment amount field itself; only "Uygula"
/// (via [Navigator.pop]) transfers its result out, per the approved
/// requirement.
class _CalculatorSheet extends StatefulWidget {
  const _CalculatorSheet();

  @override
  State<_CalculatorSheet> createState() => _CalculatorSheetState();
}

class _CalculatorSheetState extends State<_CalculatorSheet> {
  String _display = '0';
  double? _pendingValue;
  String? _pendingOperator;

  double get _currentValue => double.tryParse(_display) ?? 0;

  void _inputDigit(String digit) {
    setState(() {
      _display = _display == '0' ? digit : _display + digit;
    });
  }

  void _inputDecimal() {
    setState(() {
      if (!_display.contains('.')) _display = '$_display.';
    });
  }

  void _backspace() {
    setState(() {
      _display = _display.length > 1 ? _display.substring(0, _display.length - 1) : '0';
    });
  }

  void _clear() {
    setState(() {
      _display = '0';
      _pendingValue = null;
      _pendingOperator = null;
    });
  }

  void _applyOperator(String operatorSymbol) {
    setState(() {
      if (_pendingValue != null && _pendingOperator != null) {
        _pendingValue = _compute(_pendingValue!, _currentValue, _pendingOperator!);
      } else {
        _pendingValue = _currentValue;
      }
      _pendingOperator = operatorSymbol;
      _display = '0';
    });
  }

  void _equals() {
    setState(() {
      if (_pendingValue != null && _pendingOperator != null) {
        _display = _compute(_pendingValue!, _currentValue, _pendingOperator!).toString();
        _pendingValue = null;
        _pendingOperator = null;
      }
    });
  }

  double _compute(double a, double b, String operatorSymbol) {
    return switch (operatorSymbol) {
      '+' => a + b,
      '-' => a - b,
      '×' => a * b,
      '÷' => b == 0 ? a : a / b,
      _ => b,
    };
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Text(_display, style: AppTypography.titleLarge),
            ),
            const SizedBox(height: AppSpacing.md),
            _CalculatorGrid(
              onDigit: _inputDigit,
              onDecimal: _inputDecimal,
              onBackspace: _backspace,
              onClear: _clear,
              onOperator: _applyOperator,
              onEquals: _equals,
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(_currentValue),
                child: const Text('Uygula'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalculatorGrid extends StatelessWidget {
  const _CalculatorGrid({
    required this.onDigit,
    required this.onDecimal,
    required this.onBackspace,
    required this.onClear,
    required this.onOperator,
    required this.onEquals,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onDecimal;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final ValueChanged<String> onOperator;
  final VoidCallback onEquals;

  @override
  Widget build(BuildContext context) {
    Widget button(String label, VoidCallback onTap) {
      return OutlinedButton(onPressed: onTap, child: Text(label));
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: button('7', () => onDigit('7'))),
            Expanded(child: button('8', () => onDigit('8'))),
            Expanded(child: button('9', () => onDigit('9'))),
            Expanded(child: button('÷', () => onOperator('÷'))),
          ],
        ),
        Row(
          children: [
            Expanded(child: button('4', () => onDigit('4'))),
            Expanded(child: button('5', () => onDigit('5'))),
            Expanded(child: button('6', () => onDigit('6'))),
            Expanded(child: button('×', () => onOperator('×'))),
          ],
        ),
        Row(
          children: [
            Expanded(child: button('1', () => onDigit('1'))),
            Expanded(child: button('2', () => onDigit('2'))),
            Expanded(child: button('3', () => onDigit('3'))),
            Expanded(child: button('-', () => onOperator('-'))),
          ],
        ),
        Row(
          children: [
            Expanded(child: button('0', () => onDigit('0'))),
            Expanded(child: button('.', onDecimal)),
            Expanded(child: button('⌫', onBackspace)),
            Expanded(child: button('+', () => onOperator('+'))),
          ],
        ),
        Row(
          children: [
            Expanded(child: button('C', onClear)),
            Expanded(flex: 3, child: button('=', onEquals)),
          ],
        ),
      ],
    );
  }
}
