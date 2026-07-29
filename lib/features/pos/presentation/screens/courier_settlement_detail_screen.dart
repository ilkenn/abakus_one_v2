import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/clock_provider.dart';
import '../../../../shared/models/currency.dart';
import '../../../../shared/models/money.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../orders/domain/models/order_id.dart';
import '../../application/use_cases/record_courier_cash_collection.dart';
import '../../domain/courier_settlement/courier_cash_collection.dart';
import '../../domain/courier_settlement/courier_collection_type.dart';
import '../../domain/courier_settlement/courier_settlement_session.dart';
import '../providers/courier_settlement_dependencies_provider.dart';
import '../providers/payment_session_dependencies_provider.dart';
import 'courier_cash_declaration_screen.dart';

/// One [CourierSettlementSession]'s detail view — every recorded
/// [CourierCashCollection], plus actions to add one and to move on to
/// declaring the total. Mirrors `CashSessionScreen` (Sprint 3E).
class CourierSettlementDetailScreen extends ConsumerStatefulWidget {
  const CourierSettlementDetailScreen(
      {super.key, required this.settlementSessionId});

  final String settlementSessionId;

  @override
  ConsumerState<CourierSettlementDetailScreen> createState() =>
      _CourierSettlementDetailScreenState();
}

class _CourierSettlementDetailScreenState
    extends ConsumerState<CourierSettlementDetailScreen> {
  CourierSettlementSession? _session;
  List<CourierCashCollection>? _collections;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final session = await ref
        .read(courierSettlementSessionRepositoryProvider)
        .findById(widget.settlementSessionId);
    final collections = await ref
        .read(courierCashCollectionRepositoryProvider)
        .findBySettlementSessionId(widget.settlementSessionId);
    if (!mounted) return;
    setState(() {
      _session = session;
      _collections = collections;
    });
  }

  Future<void> _addCollection() async {
    final result = await showDialog<
        ({
          String orderId,
          String paymentSessionId,
          double amount,
          CourierCollectionType type,
        })>(
      context: context,
      builder: (context) => const _AddCollectionDialog(),
    );
    if (result == null) return;

    try {
      await RecordCourierCashCollection(
        clock: ref.read(clockProvider),
        idGenerator: ref.read(courierCashCollectionIdGeneratorProvider),
        sessionRepository: ref.read(courierSettlementSessionRepositoryProvider),
        paymentSessionRepository: ref.read(paymentSessionRepositoryProvider),
        collectionRepository: ref.read(courierCashCollectionRepositoryProvider),
        auditRepository:
            ref.read(courierSettlementAuditEntryRepositoryProvider),
      )(
        settlementSessionId: widget.settlementSessionId,
        orderId: OrderId(result.orderId),
        paymentSessionId: result.paymentSessionId,
        collectedAmount: Money.fromLegacyDoubleTry(result.amount),
        collectionType: result.type,
      );
      setState(() => _error = null);
      await _load();
    } on BusinessRuleViolation catch (e) {
      setState(() => _error = e.description);
    }
  }

  @override
  Widget build(BuildContext context) {
    final collections = _collections;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Vardiya Detayı'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Tahsilat Ekle',
            onPressed: _addCollection,
          ),
        ],
      ),
      body: SafeArea(
        child: collections == null
            ? const LoadingView(message: 'Tahsilatlar yükleniyor...')
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
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Text(_error!,
                          style: AppTypography.bodySmall
                              .copyWith(color: AppColors.error)),
                    ),
                  Expanded(
                    child: collections.isEmpty
                        ? const EmptyView(
                            icon: Icons.payments_outlined,
                            message: 'Henüz tahsilat yok',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            itemCount: collections.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: AppSpacing.sm),
                            itemBuilder: (context, index) {
                              final collection = collections[index];
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
                                          Text(collection.orderId.value,
                                              style: AppTypography.bodyMedium),
                                          Text(collection.collectionType.name,
                                              style: AppTypography.bodySmall
                                                  .copyWith(
                                                      color: AppColors
                                                          .textSecondary)),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      (collection.collectedAmount.minorUnits /
                                              100)
                                          .toStringAsFixed(2),
                                      style: AppTypography.bodyMedium,
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
                            builder: (_) => CourierCashDeclarationScreen(
                              settlementSessionId: widget.settlementSessionId,
                            ),
                          ));
                        },
                        child: const Text('Kasayı Bildir'),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _AddCollectionDialog extends StatefulWidget {
  const _AddCollectionDialog();

  @override
  State<_AddCollectionDialog> createState() => _AddCollectionDialogState();
}

class _AddCollectionDialogState extends State<_AddCollectionDialog> {
  final _orderIdController = TextEditingController();
  final _paymentSessionIdController = TextEditingController();
  final _amountController = TextEditingController();
  CourierCollectionType _type = CourierCollectionType.full;

  @override
  void dispose() {
    _orderIdController.dispose();
    _paymentSessionIdController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tahsilat Ekle'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _orderIdController,
            decoration: const InputDecoration(labelText: 'Sipariş No'),
          ),
          TextField(
            controller: _paymentSessionIdController,
            decoration: const InputDecoration(labelText: 'Ödeme Oturumu No'),
          ),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                labelText: 'Tutar (${Currency.accountingCurrency.symbol})'),
          ),
          DropdownButton<CourierCollectionType>(
            value: _type,
            isExpanded: true,
            items: [
              for (final type in CourierCollectionType.values)
                DropdownMenuItem(value: type, child: Text(type.name)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _type = value);
            },
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
            if (amount == null ||
                _orderIdController.text.trim().isEmpty ||
                _paymentSessionIdController.text.trim().isEmpty) {
              return;
            }
            Navigator.of(context).pop((
              orderId: _orderIdController.text.trim(),
              paymentSessionId: _paymentSessionIdController.text.trim(),
              amount: amount,
              type: _type,
            ));
          },
          child: const Text('Ekle'),
        ),
      ],
    );
  }
}
