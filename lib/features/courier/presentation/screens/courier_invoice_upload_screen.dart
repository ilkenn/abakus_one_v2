import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../data/courier_document_service.dart';
import '../../data/courier_pay_gateway.dart';
import '../../domain/pay/courier_pay_models.dart';
import '../providers/courier_pay_providers.dart';

/// ADR-085 stage 6A — "Fatura Yükle": the courier picks the period, sees
/// what it earned in it (lines not yet invoiced, earlier ones carried in),
/// types the invoice amount (it may differ: VAT, withholding), the invoice
/// number and a note, attaches the PDF or a photo, and sends. A period an
/// open invoice already covers cannot be sent again. Pops `true` once sent.
class CourierInvoiceUploadScreen extends ConsumerStatefulWidget {
  const CourierInvoiceUploadScreen({super.key, required this.initialRange});

  final CourierPayRange initialRange;

  @override
  ConsumerState<CourierInvoiceUploadScreen> createState() =>
      _CourierInvoiceUploadScreenState();
}

const _maxFileBytes = 5 * 1024 * 1024;

class _CourierInvoiceUploadScreenState
    extends ConsumerState<CourierInvoiceUploadScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _number = TextEditingController();
  final _note = TextEditingController();
  late CourierPayRange _range = _clampToToday(widget.initialRange);
  CourierInvoicePreview? _preview;
  String? _previewError;
  CourierPickedDocument? _file;
  String? _fileError;
  bool _sending = false;

  CourierPayRange _clampToToday(CourierPayRange range) {
    final today = isoDay(DateUtils.dateOnly(DateTime.now()));
    final to = range.toDate.compareTo(today) > 0 ? today : range.toDate;
    final from = range.fromDate.compareTo(to) > 0 ? to : range.fromDate;
    return (fromDate: from, toDate: to);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPreview());
  }

  @override
  void dispose() {
    _amount.dispose();
    _number.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    setState(() {
      _preview = null;
      _previewError = null;
    });
    try {
      final preview = await ref
          .read(courierPayGatewayProvider)
          .previewInvoice(periodFrom: _range.fromDate, periodTo: _range.toDate);
      if (!mounted) return;
      setState(() => _preview = preview);
      if (_amount.text.isEmpty && preview.earnedMinorUnits > 0) {
        _amount.text = minorUnitsToLiraText(preview.earnedMinorUnits);
      }
    } on CourierPayException catch (error) {
      if (mounted) setState(() => _previewError = error.message);
    }
  }

  Future<void> _pickRange() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 3),
      lastDate: today,
      initialDateRange: DateTimeRange(
        start: DateTime.tryParse(_range.fromDate) ?? today,
        end: DateTime.tryParse(_range.toDate) ?? today,
      ),
      helpText: 'Fatura dönemi',
      saveText: 'Seç',
    );
    if (picked == null || !mounted) return;
    if (picked.end.difference(picked.start).inDays >= courierPayMaxRangeDays) {
      setState(() => _previewError = 'Bir dönem en fazla 366 gün olabilir.');
      return;
    }
    _range = (fromDate: isoDay(picked.start), toDate: isoDay(picked.end));
    _amount.clear();
    await _loadPreview();
  }

  Future<void> _pick(
      Future<CourierPickedDocument?> Function(CourierDocumentService s)
          pick) async {
    final picked = await pick(ref.read(courierDocumentServiceProvider));
    if (picked == null || !mounted) return;
    setState(() {
      if (picked.bytes.length > _maxFileBytes) {
        _file = null;
        _fileError = 'Dosya en fazla 5 MB olabilir.';
      } else {
        _file = picked;
        _fileError = null;
      }
    });
  }

  Future<void> _send() async {
    final formOk = _formKey.currentState?.validate() ?? false;
    final file = _file;
    if (file == null) setState(() => _fileError = 'Fatura dosyasını ekleyin.');
    final preview = _preview;
    if (!formOk || file == null || preview == null || preview.overlapping) {
      return;
    }
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(courierPayGatewayProvider).submitInvoice(
            periodFrom: _range.fromDate,
            periodTo: _range.toDate,
            invoiceAmountMinorUnits: parseLiraToMinorUnits(_amount.text)!,
            invoiceNumber: _number.text.trim(),
            note: _note.text,
            bytes: file.bytes,
            contentType: file.contentType,
          );
      messenger.showSnackBar(const SnackBar(
          content: Text('Faturanız gönderildi. Onaylanınca bildirilecek.')));
      navigator.pop(true);
    } on CourierPayException catch (error) {
      messenger.showSnackBar(SnackBar(
        content: Text(error.message),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _previewCard() {
    final preview = _preview;
    if (_previewError != null) {
      return Text(_previewError!,
          key: const Key('invoicePreviewError'),
          style: AppTypography.bodyMedium.copyWith(color: AppColors.error));
    }
    if (preview == null) return const LinearProgressIndicator();
    final amount = parseLiraToMinorUnits(_amount.text);
    final difference =
        amount == null ? null : amount - preview.earnedMinorUnits;
    return AppCard(
      key: const Key('invoicePreview'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hakediş: ${formatPayAmount(preview.earnedMinorUnits)}',
              style: AppTypography.titleMedium),
          Text('${preview.lineCount} kazanç kalemi',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary)),
          if (preview.carriedLineCount > 0)
            Text(
              '${preview.carriedLineCount} kalem önceki tarihlerden, henüz '
              'faturalanmadığı için dahil edildi.',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
          if (difference != null && difference != 0)
            Text(
              'Fatura tutarı hakedişten '
              '${formatPayAmount(difference.abs())} '
              '${difference > 0 ? 'fazla' : 'eksik'} (KDV/stopaj olabilir).',
              key: const Key('invoiceDifference'),
              style: AppTypography.bodySmall.copyWith(color: AppColors.warning),
            ),
          if (preview.overlapping)
            Text(
              'Bu dönemin bir kısmı için zaten fatura gönderilmiş; başka bir '
              'dönem seçin.',
              key: const Key('invoiceOverlap'),
              style: AppTypography.bodySmall.copyWith(color: AppColors.error),
            ),
          if (!preview.overlapping && preview.lineCount == 0)
            Text('Bu dönemde faturalanacak kazanç yok.',
                style:
                    AppTypography.bodySmall.copyWith(color: AppColors.error)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final canSend = !_sending &&
        preview != null &&
        !preview.overlapping &&
        preview.lineCount > 0;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Fatura Yükle')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              OutlinedButton.icon(
                key: const Key('invoicePeriod'),
                onPressed: _sending ? null : _pickRange,
                icon: const Icon(Icons.date_range_outlined),
                label: Text('Dönem: ${_range.fromDate} – ${_range.toDate}'),
              ),
              const SizedBox(height: AppSpacing.md),
              _previewCard(),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                key: const Key('invoiceAmount'),
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Fatura tutarı', suffixText: 'TL'),
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  final minor = parseLiraToMinorUnits(v ?? '');
                  return minor == null || minor == 0
                      ? 'Geçerli bir tutar girin'
                      : null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                key: const Key('invoiceNumber'),
                controller: _number,
                maxLength: 64,
                decoration:
                    const InputDecoration(labelText: 'Fatura no / seri'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Fatura numarası gerekli' : null,
              ),
              TextFormField(
                key: const Key('invoiceNote'),
                controller: _note,
                maxLength: 300,
                decoration:
                    const InputDecoration(labelText: 'Açıklama (isteğe bağlı)'),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text('Fatura dosyası', style: AppTypography.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  OutlinedButton.icon(
                    key: const Key('invoicePickPdf'),
                    onPressed:
                        _sending ? null : () => _pick((s) => s.pickPdf()),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('PDF Seç'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('invoiceTakePhoto'),
                    onPressed: _sending
                        ? null
                        : () => _pick((s) => s.pickPhoto(fromCamera: true)),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Fotoğraf Çek'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('invoicePickPhoto'),
                    onPressed: _sending
                        ? null
                        : () => _pick((s) => s.pickPhoto(fromCamera: false)),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Galeriden Seç'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              if (_file != null)
                Text('Eklendi: ${_file!.name}',
                    key: const Key('invoiceFileName'),
                    style: AppTypography.bodySmall),
              if (_fileError != null)
                Text(_fileError!,
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.error)),
              const SizedBox(height: AppSpacing.xl),
              ElevatedButton(
                key: const Key('invoiceSend'),
                onPressed: canSend ? _send : null,
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                child: _sending
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Faturayı Gönder'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
