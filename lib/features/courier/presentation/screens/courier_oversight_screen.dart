import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../data/courier_oversight_gateway.dart';
import '../../domain/pay/courier_pay_models.dart';
import '../providers/courier_oversight_providers.dart';
import '../widgets/courier_earnings_tab.dart';

/// ADR-085 stage 6B — "Kurye Denetimi" (manager, admin, owner): every
/// payment method a courier changed at the door — old → new, courier, time —
/// with the slip photo, to mark "İncelendi". Pending ones come first. The
/// courier's cancellation requests go to the Onay Kutusu instead.
class CourierOversightScreen extends ConsumerWidget {
  const CourierOversightScreen({super.key, required this.organizationId});

  final String organizationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final changesAsync =
        ref.watch(courierPaymentChangesProvider(organizationId));
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Kurye Denetimi'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            key: const Key('oversightRefresh'),
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () =>
                ref.invalidate(courierPaymentChangesProvider(organizationId)),
          ),
        ],
      ),
      body: SafeArea(
        child: changesAsync.when(
          loading: () =>
              const LoadingView(message: 'Ödeme değişiklikleri yükleniyor...'),
          error: (error, _) => ErrorView(
            message: error is CourierOversightException
                ? error.message
                : 'Ödeme değişiklikleri yüklenemedi.',
            retryLabel: 'Tekrar Dene',
            onRetry: () =>
                ref.invalidate(courierPaymentChangesProvider(organizationId)),
          ),
          data: (changes) {
            if (changes.isEmpty) {
              return const EmptyView(
                key: Key('noPaymentChanges'),
                icon: Icons.verified_outlined,
                message: 'Kuryelerin değiştirdiği bir ödeme yöntemi yok.',
              );
            }
            final pending = changes
                .where(
                    (c) => c.status == CourierPaymentChangeStatus.pendingReview)
                .length;
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                const Text('Ödeme Yöntemi Değişiklikleri',
                    style: AppTypography.titleMedium),
                Text(
                  pending == 0
                      ? 'İnceleme bekleyen değişiklik yok.'
                      : '$pending değişiklik inceleme bekliyor.',
                  key: const Key('pendingChangeCount'),
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.md),
                for (final change in changes)
                  _ChangeCard(organizationId: organizationId, change: change),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ChangeCard extends ConsumerStatefulWidget {
  const _ChangeCard({required this.organizationId, required this.change});

  final String organizationId;
  final CourierPaymentChange change;

  @override
  ConsumerState<_ChangeCard> createState() => _ChangeCardState();
}

class _ChangeCardState extends ConsumerState<_ChangeCard> {
  bool _busy = false;

  Future<void> _showSlip() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    try {
      final bytes = await ref.read(courierOversightGatewayProvider).slipPhoto(
          organizationId: widget.organizationId,
          orderId: widget.change.orderId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          child: InteractiveViewer(
            child: Image.memory(bytes, key: const Key('slipImage')),
          ),
        ),
      );
    } on CourierOversightException catch (error) {
      messenger.showSnackBar(SnackBar(
          content: Text(error.message), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markReviewed() async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => const _NoteDialog(),
    );
    if (note == null || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    try {
      await ref.read(courierOversightGatewayProvider).markReviewed(
          organizationId: widget.organizationId,
          orderId: widget.change.orderId,
          note: note);
      messenger.showSnackBar(
          SnackBar(content: Text('${widget.change.orderNumber}: incelendi.')));
      ref.invalidate(courierPaymentChangesProvider(widget.organizationId));
    } on CourierOversightException catch (error) {
      messenger.showSnackBar(SnackBar(
          content: Text(error.message), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final change = widget.change;
    final pending = change.status == CourierPaymentChangeStatus.pendingReview;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        key: Key('paymentChange-${change.orderId}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${change.orderNumber} · ${change.courierName}',
                      style: AppTypography.bodyLarge),
                ),
                Text(change.status.label,
                    style: AppTypography.labelMedium.copyWith(
                        color:
                            pending ? AppColors.warning : AppColors.success)),
              ],
            ),
            Text('${change.fromLabel} → ${change.toLabel} · '
                '${formatPayAmount(change.amountDueMinorUnits)}'),
            Text(
              '${isoDay(change.reportedAt)} ${formatClock(change.reportedAt)}'
              '${change.reviewNote == null ? '' : ' · Not: ${change.reviewNote}'}',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (change.hasSlip)
                  OutlinedButton.icon(
                    key: Key('showSlip-${change.orderId}'),
                    onPressed: _busy ? null : _showSlip,
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('Slipi Gör'),
                  )
                else
                  Text('Nakde geçildi — slip yok.',
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textSecondary)),
                if (pending)
                  ElevatedButton(
                    key: Key('markReviewed-${change.orderId}'),
                    onPressed: _busy ? null : _markReviewed,
                    child: const Text('İncelendi'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog();

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('İncelendi olarak işaretle'),
      content: TextField(
        key: const Key('reviewNote'),
        controller: _note,
        maxLength: 300,
        decoration: const InputDecoration(labelText: 'Not (isteğe bağlı)'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        ElevatedButton(
          key: const Key('reviewConfirm'),
          onPressed: () => Navigator.of(context).pop(_note.text.trim()),
          child: const Text('İncelendi'),
        ),
      ],
    );
  }
}
