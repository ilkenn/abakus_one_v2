import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../data/courier_pay_gateway.dart';
import '../../domain/pay/courier_pay_models.dart';
import '../providers/courier_pay_providers.dart';
import 'courier_earnings_tab.dart';

/// ADR-085 stage 6A — "Faturalar" in "Kurye Vardiya & Kazanç": the
/// invoices couriers sent, newest first. A manager (own branches) or an
/// admin/owner opens the file, approves or rejects with a reason; an
/// admin/owner then pays it in full ("Tam Ödendi") or in part.
class CourierInvoiceReviewTab extends ConsumerWidget {
  const CourierInvoiceReviewTab({super.key, required this.organizationId});

  final String organizationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(courierInvoicesProvider(organizationId));
    return listAsync.when(
      loading: () => const LoadingView(message: 'Faturalar yükleniyor...'),
      error: (error, _) => ErrorView(
        message: error is CourierPayException
            ? error.message
            : 'Faturalar yüklenemedi.',
        retryLabel: 'Tekrar Dene',
        onRetry: () => ref.invalidate(courierInvoicesProvider(organizationId)),
      ),
      data: (list) {
        if (list.invoices.isEmpty) {
          return const EmptyView(
            key: Key('noCourierInvoices'),
            icon: Icons.receipt_long_outlined,
            message: 'Henüz kurye faturası yok.',
          );
        }
        final pending = list.invoices
            .where((i) => i.status == CourierInvoiceStatus.submitted)
            .toList();
        final others = list.invoices
            .where((i) => i.status != CourierInvoiceStatus.submitted)
            .toList();
        return RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(courierInvoicesProvider(organizationId)),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              if (pending.isNotEmpty) ...[
                const Text('Onay Bekleyenler',
                    style: AppTypography.titleMedium),
                for (final invoice in pending)
                  CourierInvoiceTile(
                    invoice: invoice,
                    onTap: () => _open(context, invoice, list),
                  ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (others.isNotEmpty) ...[
                const Text('Diğer Faturalar', style: AppTypography.titleMedium),
                for (final invoice in others)
                  CourierInvoiceTile(
                    invoice: invoice,
                    onTap: () => _open(context, invoice, list),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _open(
    BuildContext context,
    CourierInvoice invoice,
    CourierInvoiceList list,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _InvoiceDetailSheet(
        organizationId: organizationId,
        invoice: invoice,
        canRecordPayments: list.canRecordPayments,
      ),
    );
  }
}

class _InvoiceDetailSheet extends ConsumerStatefulWidget {
  const _InvoiceDetailSheet({
    required this.organizationId,
    required this.invoice,
    required this.canRecordPayments,
  });

  final String organizationId;
  final CourierInvoice invoice;
  final bool canRecordPayments;

  @override
  ConsumerState<_InvoiceDetailSheet> createState() =>
      _InvoiceDetailSheetState();
}

class _InvoiceDetailSheetState extends ConsumerState<_InvoiceDetailSheet> {
  bool _busy = false;

  CourierInvoice get _invoice => widget.invoice;

  Future<void> _run(Future<void> Function() action, String success) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    final navigator = Navigator.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(success)));
      ref.invalidate(courierInvoicesProvider(widget.organizationId));
      ref.invalidate(courierEarningsReportProvider);
      navigator.pop();
    } on CourierPayException catch (error) {
      messenger.showSnackBar(SnackBar(
        content: Text(error.message),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _viewFile() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    try {
      final file = await ref
          .read(courierPayGatewayProvider)
          .invoiceFile(invoiceId: _invoice.invoiceId);
      if (!mounted) return;
      if (file.contentType == 'application/pdf') {
        final opened = await ref
            .read(courierDocumentServiceProvider)
            .openPdf(file.bytes, name: 'fatura-${_invoice.invoiceId}.pdf');
        if (!opened) {
          messenger.showSnackBar(const SnackBar(
            content: Text('PDF bu cihazda açılamadı. Windows panelinden '
                'açmayı deneyin.'),
            backgroundColor: AppColors.error,
          ));
        }
      } else {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => Dialog(
            child: InteractiveViewer(
              child: Image.memory(file.bytes, key: const Key('invoiceImage')),
            ),
          ),
        );
      }
    } on CourierPayException catch (error) {
      messenger.showSnackBar(SnackBar(
        content: Text(error.message),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ReasonDialog(
        title: 'Faturayı Reddet',
        label: 'Gerekçe (kuryeye gösterilir)',
        confirm: 'Reddet',
      ),
    );
    if (reason == null || !mounted) return;
    await _run(
      () => ref.read(courierPayGatewayProvider).reviewInvoice(
            organizationId: widget.organizationId,
            invoiceId: _invoice.invoiceId,
            approve: false,
            reason: reason,
          ),
      'Fatura reddedildi; kurye yeniden gönderebilir.',
    );
  }

  Future<void> _partial() async {
    final result = await showDialog<({int amount, String date, String note})>(
      context: context,
      builder: (_) => CourierPaymentDialog(
        title: 'Kısmi Ödeme Gir',
        maxMinorUnits: _invoice.remainingMinorUnits,
      ),
    );
    if (result == null || !mounted) return;
    await _run(
      () => ref.read(courierPayGatewayProvider).recordPayment(
            organizationId: widget.organizationId,
            kind: CourierPaymentKind.invoicePayment,
            invoiceId: _invoice.invoiceId,
            amountMinorUnits: result.amount,
            paidDate: result.date,
            note: result.note,
          ),
      '${formatPayAmount(result.amount)} ödeme işlendi.',
    );
  }

  Future<void> _full() async {
    final result = await showDialog<({int amount, String date, String note})>(
      context: context,
      builder: (_) => CourierPaymentDialog(
        title: 'Tam Ödendi',
        fixedMinorUnits: _invoice.remainingMinorUnits,
      ),
    );
    if (result == null || !mounted) return;
    await _run(
      () => ref.read(courierPayGatewayProvider).recordPayment(
            organizationId: widget.organizationId,
            kind: CourierPaymentKind.invoicePayment,
            invoiceId: _invoice.invoiceId,
            full: true,
            paidDate: result.date,
            note: result.note,
          ),
      'Fatura tamamen ödendi.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final invoice = _invoice;
    final difference = invoice.differenceMinorUnits;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${invoice.courierName} — ${invoice.status.label}',
                  style: AppTypography.titleLarge),
              Text('Dönem: ${invoice.period} · ${invoice.lineCount} kalem'),
              Text('Fatura no: ${invoice.invoiceNumber}'),
              if (invoice.note != null) Text('Açıklama: ${invoice.note}'),
              const SizedBox(height: AppSpacing.sm),
              Text('Hakediş (sistem): '
                  '${formatPayAmount(invoice.earnedMinorUnits)}'),
              Text(
                  'Fatura tutarı: '
                  '${formatPayAmount(invoice.invoiceAmountMinorUnits)}',
                  style: AppTypography.titleMedium),
              if (difference != 0)
                Text(
                  'Fark: ${difference > 0 ? '+' : '-'}'
                  '${formatPayAmount(difference.abs())} (KDV/stopaj olabilir)',
                  key: const Key('invoiceReviewDifference'),
                  style: AppTypography.bodyMedium
                      .copyWith(color: AppColors.warning),
                ),
              Text('Ödenen: ${formatPayAmount(invoice.paidMinorUnits)} · '
                  'Kalan: ${formatPayAmount(invoice.remainingMinorUnits)}'),
              if (invoice.rejectReason != null)
                Text('Red gerekçesi: ${invoice.rejectReason}',
                    style: AppTypography.bodyMedium
                        .copyWith(color: AppColors.error)),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                key: const Key('invoiceViewFile'),
                onPressed: _busy ? null : _viewFile,
                icon: Icon(invoice.isPdf
                    ? Icons.picture_as_pdf_outlined
                    : Icons.image_outlined),
                label: const Text('Dosyayı Gör'),
              ),
              if (invoice.status == CourierInvoiceStatus.submitted) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        key: const Key('invoiceApprove'),
                        onPressed: _busy
                            ? null
                            : () => _run(
                                  () => ref
                                      .read(courierPayGatewayProvider)
                                      .reviewInvoice(
                                        organizationId: widget.organizationId,
                                        invoiceId: invoice.invoiceId,
                                        approve: true,
                                      ),
                                  'Fatura onaylandı.',
                                ),
                        child: const Text('Onayla'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('invoiceReject'),
                        onPressed: _busy ? null : _reject,
                        child: const Text('Reddet'),
                      ),
                    ),
                  ],
                ),
              ],
              if (widget.canRecordPayments && invoice.status.payable) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        key: const Key('invoicePayFull'),
                        onPressed: _busy ? null : _full,
                        child: const Text('Tam Ödendi'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('invoicePayPartial'),
                        onPressed: _busy ? null : _partial,
                        child: const Text('Kısmi Ödeme Gir'),
                      ),
                    ),
                  ],
                ),
              ],
              if (!widget.canRecordPayments && invoice.status.payable)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    'Ödemeyi Yönetici veya Sahip işler.',
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.label,
    required this.confirm,
  });

  final String title;
  final String label;
  final String confirm;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();
  bool _empty = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const Key('reasonField'),
        controller: _reason,
        maxLength: 300,
        decoration: InputDecoration(
          labelText: widget.label,
          errorText: _empty ? 'Gerekçe yazın' : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        ElevatedButton(
          key: const Key('reasonConfirm'),
          onPressed: () {
            final text = _reason.text.trim();
            if (text.isEmpty) {
              setState(() => _empty = true);
              return;
            }
            Navigator.of(context).pop(text);
          },
          child: Text(widget.confirm),
        ),
      ],
    );
  }
}

/// A payment's amount (unless [fixedMinorUnits] — "Tam Ödendi"), date and
/// note. The date is today or earlier.
class CourierPaymentDialog extends StatefulWidget {
  const CourierPaymentDialog({
    super.key,
    required this.title,
    this.maxMinorUnits,
    this.fixedMinorUnits,
  });

  final String title;
  final int? maxMinorUnits;
  final int? fixedMinorUnits;

  @override
  State<CourierPaymentDialog> createState() => _CourierPaymentDialogState();
}

class _CourierPaymentDialogState extends State<CourierPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = DateUtils.dateOnly(DateTime.now());

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(today.year - 1),
      lastDate: today,
      helpText: 'Ödeme tarihi',
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final fixed = widget.fixedMinorUnits;
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (fixed != null)
              Text('Ödenecek: ${formatPayAmount(fixed)}',
                  style: AppTypography.titleMedium)
            else
              TextFormField(
                key: const Key('paymentAmount'),
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Tutar',
                  suffixText: 'TL',
                  helperText: widget.maxMinorUnits == null
                      ? null
                      : 'En fazla ${formatPayAmount(widget.maxMinorUnits!)}',
                ),
                validator: (v) {
                  final minor = parseLiraToMinorUnits(v ?? '');
                  if (minor == null || minor == 0) {
                    return 'Geçerli bir tutar girin';
                  }
                  final max = widget.maxMinorUnits;
                  if (max != null && minor > max) {
                    return 'Kalan tutardan fazla olamaz';
                  }
                  return null;
                },
              ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              key: const Key('paymentDate'),
              onPressed: _pickDate,
              icon: const Icon(Icons.event_outlined),
              label: Text('Ödeme tarihi: ${isoDay(_date)}'),
            ),
            TextFormField(
              key: const Key('paymentNote'),
              controller: _note,
              maxLength: 300,
              decoration:
                  const InputDecoration(labelText: 'Açıklama (örn. Havale)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        ElevatedButton(
          key: const Key('paymentSave'),
          onPressed: () {
            if (fixed == null &&
                !(_formKey.currentState?.validate() ?? false)) {
              return;
            }
            Navigator.of(context).pop((
              amount: fixed ?? parseLiraToMinorUnits(_amount.text)!,
              date: isoDay(_date),
              note: _note.text.trim(),
            ));
          },
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
