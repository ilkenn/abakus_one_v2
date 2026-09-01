import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart' as connectivity_plus;
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/layout/app_breakpoints.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/currency.dart';
import '../../../../shared/models/money.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../application/use_cases/capture_offline_cash_payment.dart';
import '../../data/payment_gateway.dart';
import '../../data/pos_action_gateway.dart' show PosDeviceContext;
import '../../data/pos_operational_view_gateway.dart';
import '../../domain/offline/offline_outbox_status.dart';
import '../../domain/offline/offline_queued_cash_payment.dart';
import '../providers/pos_workspace_providers.dart';

/// The real, canonical AP-4 checkout panel — replaces the "Ödeme işlemi bu
/// sürümde kullanılamaz" dead-end in `pos_table_workspace_screen.dart`'s
/// `_CheckPanel`. Reached only once a check has reached `readyForPayment`
/// (AP-3's own state machine); this screen never re-derives what's
/// payable/settled itself — every figure comes from
/// `PaymentGateway.getPaymentSessionView`, re-fetched after EVERY action,
/// never accumulated from local tender history (the canonical-trust
/// invariant this whole AP-4 phase is built on).
class PosCheckoutScreen extends ConsumerStatefulWidget {
  const PosCheckoutScreen({
    super.key,
    required this.ctx,
    required this.checkId,
    required this.view,
  });

  final PosDeviceContext ctx;
  final String checkId;
  final PosTableOperationalView view;

  @override
  ConsumerState<PosCheckoutScreen> createState() => _PosCheckoutScreenState();
}

enum _LoadPhase { loading, ready, error }

class _PosCheckoutScreenState extends ConsumerState<PosCheckoutScreen> {
  _LoadPhase _phase = _LoadPhase.loading;
  Object? _loadError;
  PaymentSessionView? _session;

  bool _busy = false;
  String? _actionError;

  /// Set only while a tender/refund's OUTCOME is genuinely unknown (e.g. the
  /// HTTP round-trip itself failed/timed out after the server may already
  /// have processed it) — never cleared by assuming success or failure,
  /// only by a fresh [PaymentSessionView] confirming what actually happened.
  String? _unknownOutcomeNotice;

  connectivity_plus.Connectivity? _connectivity;
  StreamSubscription<List<connectivity_plus.ConnectivityResult>>?
      _connectivitySub;
  bool _isOffline = false;

  /// This check's own queued-but-not-yet-synced (or terminally
  /// failed/manualInterventionRequired) offline entries — refreshed from
  /// the durable outbox after every capture/sync pass. Purely a local,
  /// device-side view: never sent to the server, never substituted for
  /// [PaymentSessionView]'s own canonical figures.
  List<OfflineQueuedCashPayment> _queuedEntries = const [];
  String? _offlineSyncNotice;

  @override
  void initState() {
    super.initState();
    _connectivity = connectivity_plus.Connectivity();
    _connectivitySub = _connectivity!.onConnectivityChanged.listen((results) {
      final offline =
          results.every((r) => r == connectivity_plus.ConnectivityResult.none);
      final wasOffline = _isOffline;
      if (mounted) setState(() => _isOffline = offline);
      if (wasOffline && !offline) {
        // Reconnected — automatically resume draining this device's
        // offline queue, matching the governing requirement that recovery
        // never waits on a manual step.
        unawaited(_syncOfflineQueue());
      }
    });
    _connectivity!.checkConnectivity().then((results) {
      final offline =
          results.every((r) => r == connectivity_plus.ConnectivityResult.none);
      if (mounted) setState(() => _isOffline = offline);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> _refreshQueuedEntries() async {
    try {
      final repository =
          await ref.read(offlinePaymentOutboxRepositoryProvider.future);
      final all = await repository.findAll();
      if (!mounted) return;
      setState(() {
        _queuedEntries =
            all.where((e) => e.checkId == widget.checkId).toList();
      });
    } catch (_) {
      // Best-effort — the repository is a local device concern; a failure
      // here never blocks the canonical, server-sourced checkout UI.
    }
  }

  Future<void> _ensureOfflineLeaseOpportunistically() async {
    if (_isOffline) return;
    try {
      final ensure = await ref.read(ensureOfflineLeaseProvider.future);
      await ensure(ctx: widget.ctx);
    } catch (_) {
      // Best-effort pre-provisioning — a failure here (e.g. Firebase not
      // ready) must never block the checkout screen from loading; it only
      // means offline cash capture won't be available until a lease is
      // successfully acquired on some later online moment.
    }
  }

  Future<void> _syncOfflineQueue() async {
    try {
      final lease = await (await ref.read(offlineLeaseStoreProvider.future))
          .currentLease();
      if (lease == null) return;
      final sync = await ref.read(syncOfflinePaymentOutboxProvider.future);
      final result = await sync(ctx: widget.ctx, leaseId: lease.leaseId);
      if (!mounted) return;
      if (result.entries.isNotEmpty) {
        setState(() {
          _offlineSyncNotice = result.hasUnresolved
              ? 'Senkronizasyon tamamlandı: ${result.syncedCount} işlem '
                  'onaylandı, bazı işlemler mutabakat bekliyor (aşağıdaki '
                  'kuyruğu kontrol edin).'
              : '${result.syncedCount} offline işlem başarıyla senkronize '
                  'edildi.';
        });
      }
      await _refreshQueuedEntries();
      await _refresh();
    } catch (_) {
      // A failed sync attempt leaves every queued entry exactly as it was
      // — nothing here ever marks an entry resolved on the client's own
      // assumption. The next reconnect/manual retry tries again.
    }
  }

  Future<void> _bootstrap() async {
    final gateway = ref.read(paymentGatewayProvider);
    setState(() => _phase = _LoadPhase.loading);
    try {
      var view = await gateway.getPaymentSessionView(
        ctx: widget.ctx,
        checkId: widget.checkId,
      );
      if (!view.exists) {
        // First time this check reaches checkout — capture the canonical,
        // re-verifiable payable snapshot. Idempotent server-side for the
        // same check version, so a re-entrant call here is always safe.
        await gateway.createPaymentIntent(
            ctx: widget.ctx, checkId: widget.checkId);
        view = await gateway.getPaymentSessionView(
          ctx: widget.ctx,
          checkId: widget.checkId,
        );
      }
      if (!mounted) return;
      setState(() {
        _session = view;
        _phase = _LoadPhase.ready;
      });
      unawaited(_ensureOfflineLeaseOpportunistically());
      unawaited(_refreshQueuedEntries());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _phase = _LoadPhase.error;
      });
    }
  }

  Future<void> _refresh() async {
    try {
      final view = await ref.read(paymentGatewayProvider).getPaymentSessionView(
            ctx: widget.ctx,
            checkId: widget.checkId,
          );
      if (!mounted) return;
      setState(() => _session = view);
    } catch (_) {
      // A refresh failure never overwrites the last known-good state —
      // the UI keeps showing the last canonical snapshot rather than
      // blanking out on a transient read error.
    }
  }

  String _newIdempotencyKey() =>
      '${widget.checkId}-${DateTime.now().microsecondsSinceEpoch}';

  /// Offline capture path — never calls the network. Section 3's own
  /// requirement: "distinguish definitively offline from 'request may have
  /// reached the server'" — this branch is only ever taken when
  /// connectivity is confirmed absent, so there is no ambiguity about
  /// whether a request was sent (none was); the online branch below keeps
  /// its own, separate `outcomeUnknown` handling for that different case.
  Future<void> _submitOfflineCashTender({
    required List<Map<String, dynamic>> allocations,
  }) async {
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      final capture = await ref.read(captureOfflineCashPaymentProvider.future);
      final allocation = allocations.first;
      final currency = _currencyFor(_session!.currencyCode);
      final result = await capture(
        checkId: widget.checkId,
        paymentSessionId: _session!.sessionId!,
        subAccountId: allocation['subAccountId'] as String,
        amount: Money(allocation['amountMinorUnits'] as int, currency),
      );
      switch (result) {
        case OfflineCashPaymentCaptured():
          setState(() => _offlineSyncNotice =
              'Nakit tahsilat offline olarak kaydedildi. Bağlantı geri '
              'geldiğinde otomatik olarak senkronize edilecek.');
          await _refreshQueuedEntries();
        case OfflineCashPaymentRefused(:final reason):
          setState(() => _actionError = reason);
      }
    } catch (e) {
      setState(() =>
          _actionError = 'Offline tahsilat kaydedilemedi: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitTender({
    required String tenderType,
    required List<Map<String, dynamic>> allocations,
    int? requestedBoncukAmount,
  }) async {
    if (_busy) return;
    if (_isOffline && tenderType == 'cash') {
      await _submitOfflineCashTender(allocations: allocations);
      return;
    }
    setState(() {
      _busy = true;
      _actionError = null;
      _unknownOutcomeNotice = null;
    });
    final idempotencyKey = _newIdempotencyKey();
    try {
      final result =
          await ref.read(paymentGatewayProvider).recordPaymentAttempt(
                ctx: widget.ctx,
                checkId: widget.checkId,
                sessionId: _session!.sessionId!,
                tenderType: tenderType,
                idempotencyKey: idempotencyKey,
                allocations: allocations,
                requestedBoncukAmount: requestedBoncukAmount,
              );
      if (result.status != 'succeeded' && result.status != 'declined') {
        // timedOut (or any other non-terminal status) — a definitive
        // provider answer never arrived. Never shown as success.
        setState(() => _unknownOutcomeNotice =
            'Ödeme sonucu belirsiz (durum: ${result.status}). Lütfen aşağıdaki hareket listesini kontrol edin, aynı tutarı tekrar tahsil ETMEYİN.');
      }
      await _refresh();
    } on PaymentGatewayException catch (e) {
      if (_isTransportUncertain(e.code)) {
        setState(() => _unknownOutcomeNotice =
            'Bağlantı sorunu nedeniyle ödeme sonucu doğrulanamadı. Aşağıdaki hareket listesini kontrol edin — sonuç netleşene kadar aynı tutarı tekrar tahsil ETMEYİN.');
        await _refresh();
      } else {
        setState(() => _actionError = e.message);
      }
    } catch (e) {
      setState(() => _unknownOutcomeNotice =
          'Beklenmeyen bir bağlantı hatası oluştu. Ödeme sonucu doğrulanana kadar tekrar denemeyin — aşağıdaki hareket listesini kontrol edin.');
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _isTransportUncertain(String code) {
    // These specific FirebaseFunctionsException codes mean "we genuinely
    // don't know what the server did" (as opposed to e.g.
    // failed-precondition/invalid-argument, which are definitive
    // rejections) — never treated as success, never silently retried.
    return code == 'deadline-exceeded' ||
        code == 'unavailable' ||
        code == 'internal' ||
        code == 'cancelled' ||
        code == 'unknown';
  }

  Future<void> _submitRefund({
    required String refundType,
    required int amountMinorUnits,
    required String reasonCode,
    required String reasonMessage,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await ref.read(paymentGatewayProvider).requestPaymentRefund(
            ctx: widget.ctx,
            checkId: widget.checkId,
            refundType: refundType,
            amountMinorUnits: amountMinorUnits,
            reasonCode: reasonCode,
            reasonMessage: reasonMessage,
          );
      await _refresh();
    } on PaymentGatewayException catch (e) {
      setState(() => _actionError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Ödeme'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: switch (_phase) {
          _LoadPhase.loading =>
            const LoadingView(message: 'Ödeme bilgileri yükleniyor...'),
          _LoadPhase.error => ErrorView(
              message: 'Ödeme bilgileri yüklenemedi: $_loadError',
              onRetry: _bootstrap,
            ),
          _LoadPhase.ready => _CheckoutBody(
              checkId: widget.checkId,
              view: widget.view,
              session: _session!,
              busy: _busy,
              actionError: _actionError,
              unknownOutcomeNotice: _unknownOutcomeNotice,
              isOffline: _isOffline,
              queuedEntries: _queuedEntries,
              offlineSyncNotice: _offlineSyncNotice,
              onSyncNow: () => unawaited(_syncOfflineQueue()),
              onSubmitTender: _submitTender,
              onSubmitRefund: _submitRefund,
              onRefresh: _refresh,
            ),
        },
      ),
    );
  }
}

typedef _SubmitTenderFn = Future<void> Function({
  required String tenderType,
  required List<Map<String, dynamic>> allocations,
  int? requestedBoncukAmount,
});
typedef _SubmitRefundFn = Future<void> Function({
  required String refundType,
  required int amountMinorUnits,
  required String reasonCode,
  required String reasonMessage,
});

class _CheckoutBody extends StatelessWidget {
  const _CheckoutBody({
    required this.checkId,
    required this.view,
    required this.session,
    required this.busy,
    required this.actionError,
    required this.unknownOutcomeNotice,
    required this.isOffline,
    this.queuedEntries = const [],
    this.offlineSyncNotice,
    this.onSyncNow,
    required this.onSubmitTender,
    required this.onSubmitRefund,
    required this.onRefresh,
  });

  final String checkId;
  final PosTableOperationalView view;
  final PaymentSessionView session;
  final bool busy;
  final String? actionError;
  final String? unknownOutcomeNotice;
  final bool isOffline;
  final List<OfflineQueuedCashPayment> queuedEntries;
  final String? offlineSyncNotice;
  final VoidCallback? onSyncNow;
  final _SubmitTenderFn onSubmitTender;
  final _SubmitRefundFn onSubmitRefund;
  final Future<void> Function() onRefresh;

  String _subAccountName(String subAccountId) {
    for (final sub in view.subAccounts) {
      if (sub['id'] == subAccountId) {
        return sub['displayName'] as String? ?? 'Misafir';
      }
    }
    return subAccountId;
  }

  @override
  Widget build(BuildContext context) {
    final isCompleted = session.sessionStatus == 'completed';

    final summaryPanel = _SummaryPanel(
      session: session,
      subAccountName: _subAccountName,
      isOffline: isOffline,
      queuedEntries: queuedEntries,
      offlineSyncNotice: offlineSyncNotice,
      onSyncNow: onSyncNow,
    );

    if (isCompleted) {
      return _PaymentCompletedView(session: session, checkId: checkId);
    }

    final tenderPanel = _TenderPanel(
      checkId: checkId,
      session: session,
      busy: busy,
      actionError: actionError,
      unknownOutcomeNotice: unknownOutcomeNotice,
      subAccountName: _subAccountName,
      onSubmitTender: onSubmitTender,
      onSubmitRefund: onSubmitRefund,
      onRefresh: onRefresh,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= AppBreakpoints.tablet;
        if (isWide) {
          return Row(
            children: [
              Expanded(flex: 2, child: summaryPanel),
              const VerticalDivider(width: 1, color: AppColors.border),
              Expanded(flex: 3, child: tenderPanel),
            ],
          );
        }
        return Column(
          children: [
            summaryPanel,
            const Divider(height: 1, color: AppColors.border),
            Expanded(child: tenderPanel),
          ],
        );
      },
    );
  }
}

class _PaymentCompletedView extends StatelessWidget {
  const _PaymentCompletedView({required this.session, required this.checkId});

  final PaymentSessionView session;
  final String checkId;

  @override
  Widget build(BuildContext context) {
    final total = Money(
      session.payableAmountMinorUnits ?? 0,
      _currencyFor(session.currencyCode),
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded,
                color: AppColors.success, size: 72),
            const SizedBox(height: AppSpacing.md),
            const Text('Ödeme Tamamlandı', style: AppTypography.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text('$total',
                style: AppTypography.bodyLarge
                    .copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
              ),
              child: const Text('Masaya Dön'),
            ),
          ],
        ),
      ),
    );
  }
}

Currency _currencyFor(String? isoCode) {
  if (isoCode == null) return Currency.tryLira;
  return Currency.all.firstWhere(
    (c) => c.isoCode == isoCode,
    orElse: () => Currency.tryLira,
  );
}

/// Canonical amounts panel — every figure read directly from [session],
/// never computed from local tender history.
class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({
    required this.session,
    required this.subAccountName,
    required this.isOffline,
    this.queuedEntries = const [],
    this.offlineSyncNotice,
    this.onSyncNow,
  });

  final PaymentSessionView session;
  final String Function(String subAccountId) subAccountName;
  final bool isOffline;

  /// This check's own locally-queued offline entries — display-only, never
  /// substituted for [session]'s own canonical, server-sourced figures.
  final List<OfflineQueuedCashPayment> queuedEntries;
  final String? offlineSyncNotice;
  final VoidCallback? onSyncNow;

  @override
  Widget build(BuildContext context) {
    final currency = _currencyFor(session.currencyCode);
    final payable = Money(session.payableAmountMinorUnits ?? 0, currency);
    final settled = Money(session.settledAmountMinorUnits ?? 0, currency);
    final remaining = Money(session.remainingAmountMinorUnits, currency);

    // Locally-queued amounts NOT yet confirmed by the server (pending/
    // syncing/manualInterventionRequired — never `failed`, which never
    // happened) — folded into a device-local "not yet synced" figure,
    // always rendered separately from and never merged into `remaining`
    // itself, so the cashier can never mistake a local capture for a
    // server-confirmed settlement.
    final unsyncedEntries = queuedEntries
        .where((e) =>
            e.status == OfflineOutboxStatus.pending ||
            e.status == OfflineOutboxStatus.syncing ||
            e.status == OfflineOutboxStatus.manualInterventionRequired)
        .toList();
    final unsyncedTotal = Money(
      unsyncedEntries.fold<int>(0, (sum, e) => sum + e.amount.minorUnits),
      currency,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isOffline)
            Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: AppRadius.kSmall,
                border: Border.all(color: AppColors.warning),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off_outlined,
                      color: AppColors.warning, size: 18),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Bağlantı yok — yalnızca nakit tahsilat kuyruğa alınabilir.',
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.warning),
                    ),
                  ),
                ],
              ),
            ),
          if (offlineSyncNotice != null)
            Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.12),
                borderRadius: AppRadius.kSmall,
                border: Border.all(color: AppColors.info),
              ),
              child: Row(
                children: [
                  const Icon(Icons.sync_outlined,
                      color: AppColors.info, size: 18),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(offlineSyncNotice!,
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.info)),
                  ),
                ],
              ),
            ),
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            borderColor: AppColors.primary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AmountRow(label: 'Toplam', amount: payable),
                const Divider(color: AppColors.border),
                _AmountRow(label: 'Tahsil Edilen (Sunucu Onaylı)', amount: settled),
                if (unsyncedEntries.isNotEmpty)
                  _AmountRow(
                    label: 'Yerel — Senkronize Edilmedi',
                    amount: unsyncedTotal,
                    color: AppColors.warning,
                  ),
                _AmountRow(
                  label: 'Kalan (Sunucu)',
                  amount: remaining,
                  emphasize: true,
                  color: remaining.isPositive
                      ? AppColors.primary
                      : AppColors.success,
                ),
              ],
            ),
          ),
          if (queuedEntries.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Offline Kuyruk', style: AppTypography.labelLarge),
                if (onSyncNow != null)
                  TextButton(
                    onPressed: isOffline ? null : onSyncNow,
                    child: const Text('Şimdi Senkronize Et'),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final entry in queuedEntries)
              _OfflineQueueRow(entry: entry, currency: currency),
          ],
          const SizedBox(height: AppSpacing.md),
          const Text('Hesaplara Göre Tutar', style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          for (final alloc in session.subAccountAllocations)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(subAccountName(alloc.subAccountId),
                        style: AppTypography.bodyMedium,
                        overflow: TextOverflow.ellipsis),
                  ),
                  Text('${Money(alloc.payableAmountMinorUnits, currency)}',
                      style: AppTypography.bodyMedium),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One row in the offline-capture queue — the required distinction between
/// "paid and server-confirmed," "locally captured, awaiting sync,"
/// "outcome unknown," "rejected," and "manual reconciliation required."
class _OfflineQueueRow extends StatelessWidget {
  const _OfflineQueueRow({required this.entry, required this.currency});

  final OfflineQueuedCashPayment entry;
  final Currency currency;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (entry.status) {
      OfflineOutboxStatus.pending => ('Yerel — Senkronizasyon Bekliyor', AppColors.warning),
      OfflineOutboxStatus.syncing => ('Senkronize Ediliyor...', AppColors.info),
      OfflineOutboxStatus.synced => ('Senkronize Edildi', AppColors.success),
      OfflineOutboxStatus.failed => ('Reddedildi', AppColors.error),
      OfflineOutboxStatus.manualInterventionRequired => (
          'Sonuç Bilinmiyor — Mutabakat Gerekli',
          AppColors.error,
        ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(label,
                style: AppTypography.bodySmall.copyWith(color: color)),
          ),
          Text('${Money(entry.amount.minorUnits, currency)}',
              style: AppTypography.bodySmall),
        ],
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
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
    final style = (emphasize
            ? AppTypography.titleMedium
            : AppTypography.bodyMedium)
        .copyWith(
            color: color ??
                (emphasize ? AppColors.textPrimary : AppColors.textSecondary));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text('$amount', style: style),
        ],
      ),
    );
  }
}

const _tenderTypeLabels = {
  'cash': 'Nakit',
  'card': 'Kredi/Banka Kartı',
  'mealCard': 'Yemek Kartı',
  'boncuk': 'Boncuk',
};

/// Section 2/7's own rule: "A development adapter may demonstrate card/
/// meal-card state only when clearly identified as sandbox/emulator,
/// impossible to select in production." The real backend
/// (`paymentProviderAdapter.ts`) already fails closed outside
/// `FUNCTIONS_EMULATOR=true` regardless — this is the matching client-side
/// half, so a release-build cashier is never even offered a tender type
/// that can only ever come back declined.
const _kSandboxOnlyTenderTypes = {'card', 'mealCard'};

class _TenderPanel extends StatefulWidget {
  const _TenderPanel({
    required this.checkId,
    required this.session,
    required this.busy,
    required this.actionError,
    required this.unknownOutcomeNotice,
    required this.subAccountName,
    required this.onSubmitTender,
    required this.onSubmitRefund,
    required this.onRefresh,
  });

  final String checkId;
  final PaymentSessionView session;
  final bool busy;
  final String? actionError;
  final String? unknownOutcomeNotice;
  final String Function(String subAccountId) subAccountName;
  final _SubmitTenderFn onSubmitTender;
  final _SubmitRefundFn onSubmitRefund;
  final Future<void> Function() onRefresh;

  @override
  State<_TenderPanel> createState() => _TenderPanelState();
}

class _TenderPanelState extends State<_TenderPanel> {
  String _tenderType = 'cash';
  String? _targetSubAccountId;
  final _amountController = TextEditingController();
  final _boncukController = TextEditingController();

  @override
  void dispose() {
    _amountController.dispose();
    _boncukController.dispose();
    super.dispose();
  }

  Money _currency(int minorUnits) =>
      Money(minorUnits, _currencyFor(widget.session.currencyCode));

  int? _remainingForTarget() {
    final allocations = widget.session.subAccountAllocations;
    if (allocations.isEmpty) return null;
    final target = _targetSubAccountId ?? allocations.first.subAccountId;
    final basis = allocations
        .where((a) => a.subAccountId == target)
        .map((a) => a.payableAmountMinorUnits)
        .fold(0, (a, b) => a + b);
    final settledForTarget = widget.session.attempts
        .where(
            (a) => a.status == 'succeeded' || a.status == 'resolvedSucceeded')
        .map((a) => a.amountMinorUnits)
        .fold(0, (a, b) => a + b);
    // NOTE: this is a per-allocation UPPER BOUND helper only (fills the
    // amount field); the server independently re-verifies the real
    // per-sub-account remaining balance on every recordPaymentAttempt call
    // and is the only authority that can actually reject an over-amount.
    final overallRemaining = widget.session.remainingAmountMinorUnits;
    final targetShare = basis - (settledForTarget > basis ? basis : 0);
    return targetShare.clamp(0, overallRemaining);
  }

  void _fillRemaining() {
    final remaining =
        _remainingForTarget() ?? widget.session.remainingAmountMinorUnits;
    final whole = remaining /
        _currencyFor(widget.session.currencyCode).minorUnitsPerWhole;
    _amountController.text = whole.toStringAsFixed(2);
  }

  Future<void> _submit() async {
    final parsed = double.tryParse(_amountController.text.replaceAll(',', '.'));
    if (parsed == null || parsed <= 0) return;
    final amount = Money.fromLegacyDoubleTry(parsed);
    final allocations = widget.session.subAccountAllocations;
    if (allocations.isEmpty) return;
    final targetSubAccountId =
        _targetSubAccountId ?? allocations.first.subAccountId;

    int? requestedBoncukAmount;
    if (_tenderType == 'boncuk') {
      requestedBoncukAmount = int.tryParse(_boncukController.text.trim());
      if (requestedBoncukAmount == null || requestedBoncukAmount <= 0) return;
    }

    await widget.onSubmitTender(
      tenderType: _tenderType,
      allocations: [
        {
          'subAccountId': targetSubAccountId,
          'amountMinorUnits': amount.minorUnits,
        },
      ],
      requestedBoncukAmount: requestedBoncukAmount,
    );
    _amountController.clear();
    _boncukController.clear();
  }

  Future<void> _openRefundDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _RefundDialog(
        session: widget.session,
        onSubmit: widget.onSubmitRefund,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final allocations = session.subAccountAllocations;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.unknownOutcomeNotice != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.14),
                      borderRadius: AppRadius.kSmall,
                      border: Border.all(color: AppColors.warning),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: AppColors.warning, size: 20),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(widget.unknownOutcomeNotice!,
                              style: AppTypography.bodySmall
                                  .copyWith(color: AppColors.warning)),
                        ),
                      ],
                    ),
                  ),
                const Text('Ödeme Yöntemi', style: AppTypography.labelLarge),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final entry in _tenderTypeLabels.entries)
                      if (!kReleaseMode ||
                          !_kSandboxOnlyTenderTypes.contains(entry.key))
                        ChoiceChip(
                          label: Text(
                            _kSandboxOnlyTenderTypes.contains(entry.key)
                                ? '${entry.value} (Sandbox)'
                                : entry.value,
                          ),
                          selected: _tenderType == entry.key,
                          onSelected: (_) =>
                              setState(() => _tenderType = entry.key),
                        ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (allocations.length > 1) ...[
                  const Text('Hesap', style: AppTypography.labelLarge),
                  const SizedBox(height: AppSpacing.xs),
                  DropdownButtonFormField<String>(
                    initialValue:
                        _targetSubAccountId ?? allocations.first.subAccountId,
                    items: [
                      for (final alloc in allocations)
                        DropdownMenuItem(
                          value: alloc.subAccountId,
                          child:
                              Text(widget.subAccountName(alloc.subAccountId)),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _targetSubAccountId = value),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('checkoutAmountField'),
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(labelText: 'Tutar'),
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _fillRemaining,
                    child: const Text('Kalanı Doldur'),
                  ),
                ),
                if (_tenderType == 'boncuk')
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: TextField(
                      controller: _boncukController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Kullanılacak Boncuk Adedi'),
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    key: const Key('checkoutSubmitTenderButton'),
                    onPressed: widget.busy ? null : _submit,
                    child: widget.busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Tahsil Et'),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                const Divider(),
                const Text('Ödeme Hareketleri',
                    style: AppTypography.labelLarge),
                const SizedBox(height: AppSpacing.sm),
                if (session.attempts.isEmpty)
                  Text('Henüz ödeme alınmadı',
                      style: AppTypography.bodyMedium
                          .copyWith(color: AppColors.textSecondary))
                else
                  for (final attempt in session.attempts)
                    _AttemptRow(attempt: attempt, currencyFor: _currency),
                const SizedBox(height: AppSpacing.md),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('İade', style: AppTypography.labelLarge),
                    TextButton.icon(
                      onPressed: widget.busy || session.attempts.isEmpty
                          ? null
                          : _openRefundDialog,
                      icon: const Icon(Icons.replay_outlined, size: 18),
                      label: const Text('İade Talep Et'),
                    ),
                  ],
                ),
                if (session.refunds.isEmpty)
                  Text('Henüz iade talebi yok',
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textSecondary))
                else
                  for (final refund in session.refunds)
                    _RefundRow(refund: refund, currencyFor: _currency),
                if (widget.actionError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: ErrorView(message: widget.actionError!),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'succeeded':
    case 'resolvedSucceeded':
      return AppColors.success;
    case 'declined':
    case 'resolvedFailed':
      return AppColors.error;
    case 'timedOut':
    case 'unknownReconciliationRequired':
      return AppColors.warning;
    default:
      return AppColors.textSecondary;
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'succeeded':
      return 'Başarılı';
    case 'declined':
      return 'Reddedildi';
    case 'timedOut':
      return 'Sonuç Belirsiz';
    case 'unknownReconciliationRequired':
      return 'Doğrulama Bekliyor';
    case 'resolvedSucceeded':
      return 'Başarılı (Doğrulandı)';
    case 'resolvedFailed':
      return 'Başarısız (Doğrulandı)';
    case 'providerPending':
      return 'İşleniyor';
    default:
      return status;
  }
}

class _AttemptRow extends StatelessWidget {
  const _AttemptRow({required this.attempt, required this.currencyFor});

  final PaymentAttemptSummary attempt;
  final Money Function(int minorUnits) currencyFor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: AppCard(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          children: [
            Icon(Icons.circle, size: 10, color: _statusColor(attempt.status)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_tenderTypeLabels[attempt.tenderType] ?? attempt.tenderType} — ${currencyFor(attempt.amountMinorUnits)}',
                    style: AppTypography.bodyMedium,
                  ),
                  Text(_statusLabel(attempt.status),
                      style: AppTypography.bodySmall
                          .copyWith(color: _statusColor(attempt.status))),
                  if (attempt.declineReason != null)
                    Text(attempt.declineReason!,
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RefundRow extends StatelessWidget {
  const _RefundRow({required this.refund, required this.currencyFor});

  final RefundRequestSummary refund;
  final Money Function(int minorUnits) currencyFor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: AppCard(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${refund.refundType == 'full' ? 'Tam İade' : 'Kısmi İade'} — ${currencyFor(refund.amountMinorUnits)}',
                style: AppTypography.bodyMedium,
              ),
            ),
            Text(
              switch (refund.status) {
                'pendingApproval' => 'Onay Bekliyor',
                'succeeded' => 'Tamamlandı',
                'failed' => 'Başarısız',
                _ => refund.status,
              },
              style: AppTypography.bodySmall
                  .copyWith(color: _statusColor(refund.status)),
            ),
          ],
        ),
      ),
    );
  }
}

class _RefundDialog extends StatefulWidget {
  const _RefundDialog({required this.session, required this.onSubmit});

  final PaymentSessionView session;
  final _SubmitRefundFn onSubmit;

  @override
  State<_RefundDialog> createState() => _RefundDialogState();
}

class _RefundDialogState extends State<_RefundDialog> {
  String _refundType = 'full';
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController();
  final String _reasonCode = 'guestComplaint';
  bool _submitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  bool get _canConfirm =>
      !_submitting &&
      _reasonController.text.trim().isNotEmpty &&
      (_refundType == 'full' ||
          (double.tryParse(_amountController.text.replaceAll(',', '.')) ?? 0) >
              0);

  @override
  Widget build(BuildContext context) {
    final settled = widget.session.settledAmountMinorUnits ?? 0;
    return AlertDialog(
      title: const Text('İade Talep Et'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Tam İade'),
                    selected: _refundType == 'full',
                    onSelected: (_) => setState(() => _refundType = 'full'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Kısmi İade'),
                    selected: _refundType == 'partial',
                    onSelected: (_) => setState(() => _refundType = 'partial'),
                  ),
                ),
              ],
            ),
            if (_refundType == 'partial')
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: TextField(
                  controller: _amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Tutar'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(labelText: 'İade Nedeni'),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        ElevatedButton(
          onPressed: !_canConfirm
              ? null
              : () async {
                  setState(() => _submitting = true);
                  final amountMinorUnits = _refundType == 'full'
                      ? settled
                      : Money.fromLegacyDoubleTry(double.parse(
                              _amountController.text.replaceAll(',', '.')))
                          .minorUnits;
                  await widget.onSubmit(
                    refundType: _refundType,
                    amountMinorUnits: amountMinorUnits,
                    reasonCode: _reasonCode,
                    reasonMessage: _reasonController.text.trim(),
                  );
                  if (context.mounted) Navigator.of(context).pop();
                },
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Talebi Gönder'),
        ),
      ],
    );
  }
}
