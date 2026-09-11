import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/currency.dart';
import '../../../../shared/models/money.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../data/cash_register_gateway.dart';
import '../../data/pos_operational_view_gateway.dart';
import '../../data/z_report_printer_adapter.dart';
import '../providers/pos_workspace_providers.dart';
import '../widgets/pos_operational_rail.dart';

/// Gün Sonu (Kasa Kapanışı / Z Raporu) — AP-4's real cash-register engine
/// (`cashRegisterEngine.ts`) reused end to end: this screen adds no new
/// domain logic of its own beyond an open-table close guard and a
/// revenue-by-tender summary (both server-side, `getDailyRevenueSummary`/
/// `closeCashSession`'s own guard) — it is purely an End-of-Day-specific
/// orchestration on top of the same `CashRegisterGateway`
/// `PosCashRegisterScreen` already uses for ongoing operations.
///
/// Reachable from the POS operational rail's "Gün Sonu" button
/// (`pos_branch_overview_screen.dart`).
class EndOfDayScreen extends ConsumerStatefulWidget {
  const EndOfDayScreen({super.key});

  @override
  ConsumerState<EndOfDayScreen> createState() => _EndOfDayScreenState();
}

enum _EodPhase { loading, error, tablesOpen, noOpenSession, ready, closed }

class _EndOfDayScreenState extends ConsumerState<EndOfDayScreen> {
  _EodPhase _phase = _EodPhase.loading;
  Object? _loadError;
  List<PosBranchTableSummary> _openTables = const [];
  CashDrawerSummary? _drawer;
  CashSessionView? _session;
  DailyRevenueSummary? _revenue;
  bool _busy = false;
  String? _actionError;
  CashCountResult? _countResult;
  ZReportPrintResult? _printResult;
  String? _receiptText;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final ctx = ref.read(posDeviceContextProvider);
    if (ctx == null) return;
    setState(() {
      _phase = _EodPhase.loading;
      _loadError = null;
    });
    try {
      final overview = await ref.read(posOperationalViewGatewayProvider).getBranchOverview(
            organizationId: ctx.organizationId,
            branchId: ctx.branchId,
            deviceId: ctx.deviceId,
            deviceSessionId: ctx.deviceSessionId,
          );
      final openTables = overview.tables
          .where((t) => t.activeTableSessionId != null)
          .toList(growable: false);
      if (openTables.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _openTables = openTables;
          _phase = _EodPhase.tablesOpen;
        });
        return;
      }

      final drawers = await ref.read(cashRegisterGatewayProvider).listCashDrawers(ctx: ctx);
      CashDrawerSummary? drawerWithOpenSession;
      for (final d in drawers) {
        if (d.openSession != null) {
          drawerWithOpenSession = d;
          break;
        }
      }
      if (drawerWithOpenSession == null) {
        if (!mounted) return;
        setState(() => _phase = _EodPhase.noOpenSession);
        return;
      }

      final sessionId = drawerWithOpenSession.openSession!.sessionId;
      final session = await ref
          .read(cashRegisterGatewayProvider)
          .getCashSessionView(ctx: ctx, sessionId: sessionId);
      final revenue = await ref
          .read(cashRegisterGatewayProvider)
          .getDailyRevenueSummary(ctx: ctx, sessionId: sessionId);
      if (!mounted) return;
      setState(() {
        _drawer = drawerWithOpenSession;
        _session = session;
        _revenue = revenue;
        _phase = _EodPhase.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _phase = _EodPhase.error;
      });
    }
  }

  /// Mirrors `cashDomain.ts`'s own `expectedAmountMinorUnits` definition
  /// ("sum of every `cashMovements` doc for the session so far") — display
  /// preview only; the authoritative figure is always whatever
  /// `submitCashCount`'s server response returns.
  int _liveExpectedAmountMinorUnits() {
    final session = _session;
    if (session == null) return 0;
    final openingFloat = session.openingFloatAmountMinorUnits ?? 0;
    final movementsSum = session.movements
        .fold<int>(0, (sum, m) => sum + m.amountMinorUnits);
    return openingFloat + movementsSum;
  }

  ({String type, int amountMinorUnits}) _previewVariance(int actualAmountMinorUnits) {
    final expected = _liveExpectedAmountMinorUnits();
    final diff = actualAmountMinorUnits - expected;
    if (diff == 0) return (type: 'exact', amountMinorUnits: 0);
    return (type: diff < 0 ? 'short' : 'over', amountMinorUnits: diff.abs());
  }

  Future<void> _submitCountAndClose(int actualAmountMinorUnits) async {
    final ctx = ref.read(posDeviceContextProvider);
    final session = _session;
    if (ctx == null || session?.sessionId == null) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      final countResult = await ref.read(cashRegisterGatewayProvider).submitCashCount(
            ctx: ctx,
            sessionId: session!.sessionId!,
            actualAmountMinorUnits: actualAmountMinorUnits,
            notes: 'Gün Sonu sayımı.',
          );
      final refreshed = await ref
          .read(cashRegisterGatewayProvider)
          .getCashSessionView(ctx: ctx, sessionId: session.sessionId!);
      if (!mounted) return;
      setState(() {
        _countResult = countResult;
        _session = refreshed;
      });

      if (refreshed.status != 'approved') {
        // BR-CASH-006/007 — a non-exact variance needs a DIFFERENT manager's
        // approval (never self-approval) before closing may proceed. The
        // approval itself happens in the existing ApprovalInboxScreen
        // (admin feature) — this screen only surfaces that it's pending,
        // never re-implements approve/reject UI of its own.
        return;
      }

      await ref
          .read(cashRegisterGatewayProvider)
          .closeCashSession(ctx: ctx, sessionId: session.sessionId!);

      final revenue = _revenue;
      final content = ZReportContent(
        branchDisplayName: _drawer?.name ?? ctx.branchId,
        sessionId: session.sessionId!,
        businessDate: refreshed.businessDate ?? '',
        openedAt: DateTime.now(),
        closedAt: DateTime.now(),
        currencySymbol: _currency(0).currency.symbol,
        openingFloatMinorUnits: session.openingFloatAmountMinorUnits ?? 0,
        cashMinorUnits: revenue?.cashMinorUnits ?? 0,
        cardMinorUnits: revenue?.cardMinorUnits ?? 0,
        otherMinorUnits: revenue?.otherMinorUnits ?? 0,
        totalMinorUnits: revenue?.totalMinorUnits ?? 0,
        expectedAmountMinorUnits: countResult.expectedAmountMinorUnits,
        actualAmountMinorUnits: actualAmountMinorUnits,
        varianceType: countResult.varianceType,
        varianceAmountMinorUnits: countResult.varianceAmountMinorUnits,
      );
      final printResult = await const UnconfiguredZReportPrinterAdapter().print(content);
      if (!mounted) return;
      setState(() {
        _receiptText = content.toReceiptText();
        _printResult = printResult;
        _phase = _EodPhase.closed;
      });
    } on CashRegisterGatewayException catch (e) {
      setState(() => _actionError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Money _currency(int minorUnits) {
    final code = _session?.currencyCode ?? Currency.tryLira.isoCode;
    return Money(
      minorUnits,
      Currency.all.firstWhere((c) => c.isoCode == code, orElse: () => Currency.tryLira),
    );
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
                  : _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_phase) {
      case _EodPhase.loading:
        return const LoadingView(message: 'Gün sonu durumu kontrol ediliyor...');
      case _EodPhase.error:
        return ErrorView(
          message: 'Gün sonu bilgileri yüklenemedi: $_loadError',
          retryLabel: 'Tekrar Dene',
          onRetry: _load,
        );
      case _EodPhase.tablesOpen:
        return _OpenTablesWarning(tables: _openTables, onRetry: _load);
      case _EodPhase.noOpenSession:
        return const EmptyView(
          icon: Icons.point_of_sale_outlined,
          message: 'Kapatılacak açık bir kasa oturumu bulunamadı.',
        );
      case _EodPhase.ready:
        return _ReadyView(
          session: _session!,
          revenue: _revenue,
          busy: _busy,
          actionError: _actionError,
          countResult: _countResult,
          currencyOf: _currency,
          previewVariance: _previewVariance,
          onSubmit: _submitCountAndClose,
        );
      case _EodPhase.closed:
        return _ClosedView(
          receiptText: _receiptText ?? '',
          printResult: _printResult,
        );
    }
  }
}

class _OpenTablesWarning extends StatelessWidget {
  const _OpenTablesWarning({required this.tables, required this.onRetry});
  final List<PosBranchTableSummary> tables;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppCard(
            borderColor: AppColors.error.withValues(alpha: 0.4),
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: AppColors.error, size: 28),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        '${tables.length} masa hâlâ açık — gün sonu kapanışı kilitli',
                        style: AppTypography.titleMedium
                            .copyWith(color: AppColors.error, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'Kasayı kapatmadan önce tüm masaların hesabı kapatılmalı.',
                  style: AppTypography.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: ListView.separated(
              itemCount: tables.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xs),
              itemBuilder: (context, index) {
                final table = tables[index];
                return AppCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Text(table.displayName, style: AppTypography.bodyLarge),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Tekrar Kontrol Et'),
          ),
        ],
      ),
    );
  }
}

class _ReadyView extends StatefulWidget {
  const _ReadyView({
    required this.session,
    required this.revenue,
    required this.busy,
    required this.actionError,
    required this.countResult,
    required this.currencyOf,
    required this.previewVariance,
    required this.onSubmit,
  });

  final CashSessionView session;
  final DailyRevenueSummary? revenue;
  final bool busy;
  final String? actionError;
  final CashCountResult? countResult;
  final Money Function(int) currencyOf;
  final ({String type, int amountMinorUnits}) Function(int) previewVariance;
  final Future<void> Function(int actualAmountMinorUnits) onSubmit;

  @override
  State<_ReadyView> createState() => _ReadyViewState();
}

class _ReadyViewState extends State<_ReadyView> {
  final _controller = TextEditingController();
  int? _typedMinorUnits;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _varianceLabel(String type) => switch (type) {
        'over' => 'Fazla',
        'short' => 'Eksik',
        _ => 'Tam',
      };

  Color _varianceColor(String type) => switch (type) {
        'over' => AppColors.warning,
        'short' => AppColors.error,
        _ => AppColors.success,
      };

  bool get _needsManagerApproval => widget.session.status == 'pendingApproval';

  @override
  Widget build(BuildContext context) {
    final revenue = widget.revenue;
    final preview = _typedMinorUnits != null ? widget.previewVariance(_typedMinorUnits!) : null;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Günün Ciro Özeti', style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: AppSpacing.sm),
          if (revenue == null)
            const LoadingView(message: 'Ciro özeti yükleniyor...')
          else
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _RevenueRow(label: 'Nakit', value: widget.currencyOf(revenue.cashMinorUnits)),
                  _RevenueRow(label: 'Kredi Kartı', value: widget.currencyOf(revenue.cardMinorUnits)),
                  _RevenueRow(label: 'Diğer', value: widget.currencyOf(revenue.otherMinorUnits)),
                  const Divider(),
                  _RevenueRow(
                    label: 'Toplam Ciro',
                    value: widget.currencyOf(revenue.totalMinorUnits),
                    bold: true,
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          Text('Kasa Sayımı', style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Açılış Bakiyesi: ${widget.currencyOf(widget.session.openingFloatAmountMinorUnits ?? 0)}',
            style: AppTypography.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            key: const Key('actualAmountField'),
            controller: _controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Sayılan Tutar (₺)',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) {
              final parsed = double.tryParse(value.replaceAll(',', '.'));
              setState(() => _typedMinorUnits = parsed == null ? null : (parsed * 100).round());
            },
          ),
          if (preview != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Tahmini Fark: ${_varianceLabel(preview.type)} ${widget.currencyOf(preview.amountMinorUnits)}',
              style: AppTypography.bodyMedium.copyWith(
                color: _varianceColor(preview.type),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
          if (widget.countResult != null) ...[
            const SizedBox(height: AppSpacing.md),
            AppCard(
              borderColor: _varianceColor(widget.countResult!.varianceType).withValues(alpha: 0.4),
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                'Sunucu Sonucu — Beklenen ${widget.currencyOf(widget.countResult!.expectedAmountMinorUnits)} · '
                '${_varianceLabel(widget.countResult!.varianceType)} ${widget.currencyOf(widget.countResult!.varianceAmountMinorUnits)}',
                style: AppTypography.bodyMedium,
              ),
            ),
          ],
          if (_needsManagerApproval) ...[
            const SizedBox(height: AppSpacing.md),
            AppCard(
              borderColor: AppColors.warning.withValues(alpha: 0.4),
              padding: const EdgeInsets.all(AppSpacing.md),
              child: const Text(
                'Sayım kaydedildi. Kasa kapanışı için bir yöneticinin '
                'Onay Kutusu\'ndan bu sayımı onaylaması gerekiyor.',
                style: AppTypography.bodyMedium,
              ),
            ),
          ],
          if (widget.actionError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(widget.actionError!,
                style: AppTypography.bodySmall.copyWith(color: AppColors.error)),
          ],
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: widget.busy || _typedMinorUnits == null
                  ? null
                  : () => widget.onSubmit(_typedMinorUnits!),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              ),
              icon: const Icon(Icons.print_outlined),
              label: const Text('Günü Kapat ve Z Raporu Al'),
            ),
          ),
        ],
      ),
    );
  }
}

class _RevenueRow extends StatelessWidget {
  const _RevenueRow({required this.label, required this.value, this.bold = false});
  final String label;
  final Money value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = bold
        ? AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold)
        : AppTypography.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text('$value', style: style),
        ],
      ),
    );
  }
}

class _ClosedView extends StatelessWidget {
  const _ClosedView({required this.receiptText, required this.printResult});
  final String receiptText;
  final ZReportPrintResult? printResult;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 28),
              const SizedBox(width: AppSpacing.sm),
              Text('Gün kapatıldı',
                  style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (printResult != null && !printResult!.succeeded)
            Text(printResult!.message,
                style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: AppSpacing.md),
          Text('Yazdırmaya Hazır — Z Raporu',
              style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: SelectableText(
              receiptText,
              style: AppTypography.bodySmall.copyWith(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}
