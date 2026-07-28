import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../../shared/widgets/layout/app_section_header.dart';
import '../../../orders/domain/models/order.dart';
import '../../domain/authorization/authorization_result.dart';
import '../../domain/authorization/pos_authorization_policy.dart';
import '../../domain/authorization/pos_authorized_action.dart';
import '../providers/closed_account_detail_provider.dart';

/// Detail view for one [OrderClosure] — status, closure metadata, and its
/// full [ClosureAuditEntry] timeline, plus a reopen action and a
/// duplicate-receipt request action.
///
/// **Standalone this sprint, deliberately not wired to any route** — same
/// reasoning as [ClosedAccountsScreen]: [authorizationPolicy] has no
/// production implementation. [order] is a required, caller-supplied
/// parameter rather than looked up by id — this codebase has no
/// `Order`-by-id repository yet (only a submitted-orders list), a gap
/// flagged in this sprint's final report rather than papered over with a
/// new repository beyond this sprint's scope.
///
/// **Payment method correction and void are not exposed with dedicated UI
/// forms in this screen** — `CorrectPaymentMethod`/`VoidPayment` are fully
/// built, tested application-layer use cases, but the multi-field forms
/// they need (target split picker, new method picker, reason, reference
/// numbers) were judged out of this sprint's UI-completeness bar; reopen
/// and duplicate-receipt (both single-reason-field actions) are wired as
/// the representative examples of this screen's action pattern.
class ClosedAccountDetailScreen extends ConsumerStatefulWidget {
  const ClosedAccountDetailScreen({
    super.key,
    required this.closureId,
    required this.order,
    required this.authorizationPolicy,
    required this.viewerStaffId,
  });

  final String closureId;
  final Order order;
  final PosAuthorizationPolicy authorizationPolicy;
  final String viewerStaffId;

  @override
  ConsumerState<ClosedAccountDetailScreen> createState() =>
      _ClosedAccountDetailScreenState();
}

class _ClosedAccountDetailScreenState
    extends ConsumerState<ClosedAccountDetailScreen> {
  AuthorizationResult? _authorization;
  int _duplicateReceiptRequestCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final authorization = await widget.authorizationPolicy.authorize(
      action: PosAuthorizedAction.viewClosedAccount,
      actorStaffId: widget.viewerStaffId,
      context: {'closureId': widget.closureId},
    );
    if (!mounted) return;
    setState(() => _authorization = authorization);
    if (!authorization.granted) return;

    await ref.read(closedAccountDetailProvider.notifier).load(
          closureId: widget.closureId,
          orderId: widget.order.id,
        );
  }

  Future<void> _requestReopen() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _ReasonDialog(title: 'Hesabı Yeniden Aç'),
    );
    if (reason == null || reason.isEmpty) return;
    await ref.read(closedAccountDetailProvider.notifier).reopen(
          authorizationPolicy: widget.authorizationPolicy,
          reason: reason,
          performedByStaffId: widget.viewerStaffId,
        );
  }

  Future<void> _requestDuplicateReceipt() async {
    _duplicateReceiptRequestCount += 1;
    final result = await ref
        .read(closedAccountDetailProvider.notifier)
        .requestDuplicateReceipt(
          order: widget.order,
          requestedByStaffId: widget.viewerStaffId,
          requestId: 'req-$_duplicateReceiptRequestCount',
        );
    if (!mounted || result == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Fiş yazdırma: ${result.status.name}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authorization = _authorization;
    final state = ref.watch(closedAccountDetailProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Hesap ${widget.order.orderNumber.value}'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: authorization == null
            ? const LoadingView(message: 'Yetki kontrol ediliyor...')
            : !authorization.granted
                ? ErrorView(
                    message: authorization.reason ??
                        'Bu ekranı görüntüleme yetkiniz yok.',
                  )
                : state.closure == null
                    ? const LoadingView()
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AppCard(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Durum: ${state.closure!.lifecycleStatus.name}',
                                    style: AppTypography.bodyLarge,
                                  ),
                                  Text(
                                    'Kapatan: ${state.closure!.closedByStaffId ?? "-"}',
                                    style: AppTypography.bodyMedium,
                                  ),
                                  Text(
                                    'Yeniden açma sayısı: ${state.closure!.reopenCount}',
                                    style: AppTypography.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            if (state.error != null)
                              Padding(
                                padding: const EdgeInsets.only(
                                    bottom: AppSpacing.md),
                                child: ErrorView(message: state.error!),
                              ),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed:
                                        state.isBusy ? null : _requestReopen,
                                    child: const Text('Yeniden Aç'),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: state.isBusy
                                        ? null
                                        : _requestDuplicateReceipt,
                                    child: const Text('Fiş Tekrar Yazdır'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            const AppSectionHeader(title: 'Denetim Kaydı'),
                            const SizedBox(height: AppSpacing.sm),
                            for (final entry in state.auditEntries)
                              Padding(
                                padding: const EdgeInsets.only(
                                    bottom: AppSpacing.xs),
                                child: AppCard(
                                  padding: const EdgeInsets.all(AppSpacing.sm),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(entry.type.name,
                                          style: AppTypography.bodyMedium),
                                      Text(
                                        entry.description,
                                        style: AppTypography.bodySmall.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
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
  const _ReasonDialog({required this.title});

  final String title;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(labelText: 'Gerekçe'),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Onayla'),
        ),
      ],
    );
  }
}
