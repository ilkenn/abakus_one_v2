import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/currency.dart';
import '../../../../shared/models/money.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../admin/presentation/screens/approval_inbox_screen.dart';
import '../../data/cash_register_gateway.dart';
import '../../data/pos_action_gateway.dart' show PosDeviceContext;
import '../providers/pos_workspace_providers.dart';
import '../widgets/pos_operational_rail.dart';

/// The real AP-4 Wave B/D cash register screen — drawer list, session
/// open (on-site or remote-approved), non-sale movement/adjustment
/// requests, cash count submission, and close. Reachable from the POS
/// operational rail's "Kasa" button
/// (`pos_branch_overview_screen.dart`/`pos_table_workspace_screen.dart`).
/// Manager approval itself happens in the existing real
/// `ApprovalInboxScreen` — this screen only submits requests and shows
/// their status, never re-implements approve/reject UI of its own.
class PosCashRegisterScreen extends ConsumerStatefulWidget {
  const PosCashRegisterScreen({super.key});

  @override
  ConsumerState<PosCashRegisterScreen> createState() =>
      _PosCashRegisterScreenState();
}

enum _LoadPhase { loading, ready, error }

class _PosCashRegisterScreenState extends ConsumerState<PosCashRegisterScreen> {
  _LoadPhase _phase = _LoadPhase.loading;
  Object? _loadError;
  List<CashDrawerSummary> _drawers = const [];
  String? _selectedSessionId;
  CashSessionView? _session;
  bool _busy = false;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final ctx = ref.read(posDeviceContextProvider);
    if (ctx == null) return;
    setState(() => _phase = _LoadPhase.loading);
    try {
      final drawers =
          await ref.read(cashRegisterGatewayProvider).listCashDrawers(ctx: ctx);
      if (!mounted) return;
      setState(() {
        _drawers = drawers;
        _phase = _LoadPhase.ready;
      });
      if (_selectedSessionId != null) await _refreshSession();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _phase = _LoadPhase.error;
      });
    }
  }

  Future<void> _refreshSession() async {
    final ctx = ref.read(posDeviceContextProvider);
    final sessionId = _selectedSessionId;
    if (ctx == null || sessionId == null) return;
    try {
      final view = await ref
          .read(cashRegisterGatewayProvider)
          .getCashSessionView(ctx: ctx, sessionId: sessionId);
      if (!mounted) return;
      setState(() => _session = view);
    } catch (_) {
      // Keep the last known-good snapshot on a transient read failure.
    }
  }

  Future<void> _selectSession(String sessionId) async {
    setState(() {
      _selectedSessionId = sessionId;
      _session = null;
    });
    await _refreshSession();
  }

  Future<void> _createDrawer(String name) async {
    final ctx = ref.read(posDeviceContextProvider);
    if (ctx == null) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await ref.read(cashRegisterGatewayProvider).createCashDrawer(
            ctx: ctx,
            name: name,
          );
      await _load();
    } on CashRegisterGatewayException catch (e) {
      setState(() => _actionError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitOpenSession({
    required String drawerId,
    required int openingFloatAmountMinorUnits,
    required String reason,
  }) async {
    final ctx = ref.read(posDeviceContextProvider);
    if (ctx == null) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      final result =
          await ref.read(cashRegisterGatewayProvider).requestCashSessionOpen(
                ctx: ctx,
                drawerId: drawerId,
                openingFloatAmountMinorUnits: openingFloatAmountMinorUnits,
                currencyCode: Currency.tryLira.isoCode,
                reason: reason,
              );
      await _load();
      await _selectSession(result.sessionId);
    } on CashRegisterGatewayException catch (e) {
      setState(() => _actionError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitMovement({
    required String movementType,
    required int amountMinorUnits,
    required String reason,
  }) async {
    final ctx = ref.read(posDeviceContextProvider);
    final sessionId = _selectedSessionId;
    if (ctx == null || sessionId == null) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await ref.read(cashRegisterGatewayProvider).requestCashMovement(
            ctx: ctx,
            sessionId: sessionId,
            movementType: movementType,
            amountMinorUnits: amountMinorUnits,
            reason: reason,
          );
      await _refreshSession();
    } on CashRegisterGatewayException catch (e) {
      setState(() => _actionError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitCount({
    required int actualAmountMinorUnits,
    required String notes,
  }) async {
    final ctx = ref.read(posDeviceContextProvider);
    final sessionId = _selectedSessionId;
    if (ctx == null || sessionId == null) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await ref.read(cashRegisterGatewayProvider).submitCashCount(
            ctx: ctx,
            sessionId: sessionId,
            actualAmountMinorUnits: actualAmountMinorUnits,
            notes: notes,
          );
      await _refreshSession();
    } on CashRegisterGatewayException catch (e) {
      setState(() => _actionError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _closeSession() async {
    final ctx = ref.read(posDeviceContextProvider);
    final sessionId = _selectedSessionId;
    if (ctx == null || sessionId == null) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await ref
          .read(cashRegisterGatewayProvider)
          .closeCashSession(ctx: ctx, sessionId: sessionId);
      await _load();
      await _refreshSession();
    } on CashRegisterGatewayException catch (e) {
      setState(() => _actionError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctx = ref.watch(posDeviceContextProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Row(
          children: [
            const PosOperationalRail(),
            Expanded(
              child: ctx == null
                  ? const Center(child: Text('Cihaz oturumu gerekli.'))
                  : _buildContent(ctx),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(PosDeviceContext ctx) {
    switch (_phase) {
      case _LoadPhase.loading:
        return const LoadingView(message: 'Kasalar yükleniyor...');
      case _LoadPhase.error:
        return ErrorView(
          message: 'Kasalar yüklenemedi: $_loadError',
          onRetry: _load,
        );
      case _LoadPhase.ready:
        return Row(
          children: [
            Expanded(
              flex: 2,
              child: _DrawerListPanel(
                drawers: _drawers,
                busy: _busy,
                selectedSessionId: _selectedSessionId,
                onCreateDrawer: _createDrawer,
                onOpenSessionRequested: _submitOpenSession,
                onSelectSession: _selectSession,
              ),
            ),
            const VerticalDivider(width: 1, color: AppColors.border),
            Expanded(
              flex: 3,
              child: _session == null
                  ? const Center(child: Text('Bir kasa seçin veya kasa açın.'))
                  : _SessionDetailPanel(
                      session: _session!,
                      busy: _busy,
                      actionError: _actionError,
                      onSubmitMovement: _submitMovement,
                      onSubmitCount: _submitCount,
                      onClose: _closeSession,
                      onRefresh: _refreshSession,
                    ),
            ),
          ],
        );
    }
  }
}

String _statusLabel(String status) {
  return switch (status) {
    'awaitingOpenApproval' => 'Açılış Onayı Bekliyor',
    'openRejected' => 'Açılış Reddedildi',
    'active' => 'Açık',
    'pendingApproval' => 'Sayım Onayı Bekliyor',
    'approved' => 'Onaylandı (Kapatılabilir)',
    'rejected' => 'Sayım Reddedildi',
    'closed' => 'Kapalı',
    _ => status,
  };
}

Color _statusColor(String status) {
  return switch (status) {
    'active' || 'approved' => AppColors.success,
    'awaitingOpenApproval' || 'pendingApproval' => AppColors.warning,
    'openRejected' || 'rejected' => AppColors.error,
    'closed' => AppColors.textSecondary,
    _ => AppColors.textSecondary,
  };
}

class _DrawerListPanel extends StatelessWidget {
  const _DrawerListPanel({
    required this.drawers,
    required this.busy,
    required this.selectedSessionId,
    required this.onCreateDrawer,
    required this.onOpenSessionRequested,
    required this.onSelectSession,
  });

  final List<CashDrawerSummary> drawers;
  final bool busy;
  final String? selectedSessionId;
  final Future<void> Function(String name) onCreateDrawer;
  final Future<void> Function({
    required String drawerId,
    required int openingFloatAmountMinorUnits,
    required String reason,
  }) onOpenSessionRequested;
  final Future<void> Function(String sessionId) onSelectSession;

  Future<void> _showCreateDrawerDialog(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Yeni Kasa'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Kasa Adı'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: controller.text.trim().isEmpty
                ? null
                : () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Oluştur'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) await onCreateDrawer(name);
  }

  Future<void> _showOpenSessionDialog(
      BuildContext context, String drawerId) async {
    final amountController = TextEditingController(text: '0');
    final reasonController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Kasa Aç'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Açılış Bakiyesi'),
              ),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(labelText: 'Açıklama'),
                onChanged: (_) => setDialogState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Vazgeç'),
            ),
            ElevatedButton(
              onPressed: reasonController.text.trim().isEmpty
                  ? null
                  : () async {
                      final amount = Money.fromLegacyDoubleTry(double.tryParse(
                              amountController.text.replaceAll(',', '.')) ??
                          0);
                      Navigator.of(dialogContext).pop();
                      await onOpenSessionRequested(
                        drawerId: drawerId,
                        openingFloatAmountMinorUnits: amount.minorUnits,
                        reason: reasonController.text.trim(),
                      );
                    },
              child: const Text('Kasayı Aç'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Kasalar', style: AppTypography.titleMedium),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Yeni Kasa',
                onPressed: busy ? null : () => _showCreateDrawerDialog(context),
              ),
            ],
          ),
        ),
        Expanded(
          child: drawers.isEmpty
              ? const EmptyView(
                  icon: Icons.point_of_sale_outlined,
                  message: 'Henüz kayıtlı kasa yok.',
                )
              : ListView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  children: [
                    for (final drawer in drawers)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: InkWell(
                          borderRadius: AppRadius.kMedium,
                          onTap: busy
                              ? null
                              : drawer.openSession != null
                                  ? () => onSelectSession(
                                      drawer.openSession!.sessionId)
                                  : () => _showOpenSessionDialog(
                                      context, drawer.drawerId),
                          child: AppCard(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            borderColor: drawer.openSession != null
                                ? selectedSessionId ==
                                        drawer.openSession!.sessionId
                                    ? AppColors.primary
                                    : _statusColor(drawer.openSession!.status)
                                : null,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(drawer.name,
                                    style: AppTypography.bodyLarge),
                                const SizedBox(height: 4),
                                if (drawer.openSession != null)
                                  Text(
                                    _statusLabel(drawer.openSession!.status),
                                    style: AppTypography.bodySmall.copyWith(
                                        color: _statusColor(
                                            drawer.openSession!.status)),
                                  )
                                else
                                  Text('Kapalı — açmak için dokunun',
                                      style: AppTypography.bodySmall.copyWith(
                                          color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

const _movementTypeLabels = {
  'manualIn': 'Nakit Giriş',
  'manualOut': 'Nakit Çıkış',
  'safeDeposit': 'Kasa Teslim',
  'pettyCash': 'Küçük Kasa',
  'expense': 'Gider',
};

class _SessionDetailPanel extends StatelessWidget {
  const _SessionDetailPanel({
    required this.session,
    required this.busy,
    required this.actionError,
    required this.onSubmitMovement,
    required this.onSubmitCount,
    required this.onClose,
    required this.onRefresh,
  });

  final CashSessionView session;
  final bool busy;
  final String? actionError;
  final Future<void> Function({
    required String movementType,
    required int amountMinorUnits,
    required String reason,
  }) onSubmitMovement;
  final Future<void> Function({
    required int actualAmountMinorUnits,
    required String notes,
  }) onSubmitCount;
  final Future<void> Function() onClose;
  final Future<void> Function() onRefresh;

  Money _currency(int minorUnits) => Money(
      minorUnits,
      Currency.all.firstWhere(
        (c) => c.isoCode == session.currencyCode,
        orElse: () => Currency.tryLira,
      ));

  Future<void> _showMovementDialog(BuildContext context) async {
    String type = 'manualIn';
    final amountController = TextEditingController();
    final reasonController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Kasa Hareketi Talep Et'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: type,
                items: [
                  for (final entry in _movementTypeLabels.entries)
                    DropdownMenuItem(
                        value: entry.key, child: Text(entry.value)),
                ],
                onChanged: (value) =>
                    setDialogState(() => type = value ?? type),
              ),
              TextField(
                controller: amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Tutar'),
                onChanged: (_) => setDialogState(() {}),
              ),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(labelText: 'Açıklama'),
                onChanged: (_) => setDialogState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Vazgeç'),
            ),
            ElevatedButton(
              onPressed: reasonController.text.trim().isEmpty ||
                      (double.tryParse(
                                  amountController.text.replaceAll(',', '.')) ??
                              0) <=
                          0
                  ? null
                  : () async {
                      final amount = Money.fromLegacyDoubleTry(double.parse(
                          amountController.text.replaceAll(',', '.')));
                      Navigator.of(dialogContext).pop();
                      await onSubmitMovement(
                        movementType: type,
                        amountMinorUnits: amount.minorUnits,
                        reason: reasonController.text.trim(),
                      );
                    },
              child: const Text('Talebi Gönder'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCountDialog(BuildContext context) async {
    final amountController = TextEditingController();
    final notesController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Sayım Gir'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Sayılan Tutar'),
                onChanged: (_) => setDialogState(() {}),
              ),
              TextField(
                controller: notesController,
                decoration:
                    const InputDecoration(labelText: 'Not (isteğe bağlı)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Vazgeç'),
            ),
            ElevatedButton(
              onPressed:
                  double.tryParse(amountController.text.replaceAll(',', '.')) ==
                          null
                      ? null
                      : () async {
                          final amount = Money.fromLegacyDoubleTry(double.parse(
                              amountController.text.replaceAll(',', '.')));
                          Navigator.of(dialogContext).pop();
                          await onSubmitCount(
                            actualAmountMinorUnits: amount.minorUnits,
                            notes: notesController.text.trim(),
                          );
                        },
              child: const Text('Sayımı Gönder'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Kasa Oturumu', style: AppTypography.titleMedium),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(session.status ?? '')
                        .withValues(alpha: 0.12),
                    borderRadius: AppRadius.kPill,
                  ),
                  child: Text(
                    _statusLabel(session.status ?? ''),
                    style: AppTypography.bodySmall.copyWith(
                        color: _statusColor(session.status ?? ''),
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('İş Günü: ${session.businessDate ?? '-'}',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.md),
            if (session.status == 'awaitingOpenApproval' ||
                session.status == 'pendingApproval')
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: AppRadius.kSmall,
                  border: Border.all(color: AppColors.warning),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.hourglass_top_rounded,
                        color: AppColors.warning, size: 18),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        'Yönetici onayı bekleniyor. Onay Kutusu\'ndan işlem yapılabilir.',
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.warning),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const ApprovalInboxScreen()),
                      ),
                      child: const Text('Onay Kutusu'),
                    ),
                  ],
                ),
              ),
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      'Açılış Bakiyesi: ${_currency(session.openingFloatAmountMinorUnits ?? 0)}'),
                  Text(
                      'Güncel Bakiye: ${_currency(session.settledAmountMinorUnits ?? 0)}'),
                  Text(
                      'Kasa Modeli: ${session.cashRegisterModel == 'cashierBound' ? 'Kasiyer Bazlı' : 'Ortak Kasa'}'),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (session.status == 'active')
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  OutlinedButton(
                    onPressed: busy ? null : () => _showMovementDialog(context),
                    child: const Text('Nakit Hareketi Talep Et'),
                  ),
                  ElevatedButton(
                    onPressed: busy ? null : () => _showCountDialog(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                    ),
                    child: const Text('Sayım Gir'),
                  ),
                ],
              ),
            if (session.status == 'approved')
              ElevatedButton(
                onPressed: busy ? null : onClose,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                ),
                child: const Text('Kasayı Kapat'),
              ),
            if (actionError != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: ErrorView(message: actionError!),
              ),
            const SizedBox(height: AppSpacing.lg),
            const Text('Hareketler', style: AppTypography.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            if (session.movements.isEmpty)
              Text('Henüz hareket yok',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary))
            else
              for (final movement in session.movements)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          _movementTypeLabels[movement.type] ?? movement.type,
                          style: AppTypography.bodySmall,
                        ),
                      ),
                      Text('${_currency(movement.amountMinorUnits)}',
                          style: AppTypography.bodySmall),
                    ],
                  ),
                ),
            const SizedBox(height: AppSpacing.md),
            const Text('Sayımlar', style: AppTypography.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            if (session.counts.isEmpty)
              Text('Henüz sayım yok',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary))
            else
              for (final count in session.counts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Beklenen ${_currency(count.expectedAmountMinorUnits)} · Sayılan ${_currency(count.actualAmountMinorUnits)} · ${count.variance.type == 'exact' ? 'Tam' : count.variance.type == 'over' ? 'Fazla' : 'Eksik'} ${_currency(count.variance.amountMinorUnits)}',
                    style: AppTypography.bodySmall,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
