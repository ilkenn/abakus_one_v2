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
import '../providers/admin_financial_list_providers.dart';

Currency _currencyFor(String? isoCode) {
  if (isoCode == null) return Currency.tryLira;
  return Currency.all.firstWhere(
    (c) => c.isoCode == isoCode,
    orElse: () => Currency.tryLira,
  );
}

String _formatDate(DateTime dt) {
  final local = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}

/// AP-4 Wave D — Admin's real, branch-wide financial oversight
/// destination: payment sessions, refunds, cash sessions, the fiscal
/// operation journal (with an unresolved-only reconciliation-queue
/// filter), and offline authorization leases. Every tab is backed by one
/// of `adminFinancialView.ts`'s five real callables
/// (`admin_financial_list_providers.dart`) — read-only by design (see
/// `AdminFinancialGateway`'s own doc comment for why mutations live
/// elsewhere).
class AdminFinancialOperationsScreen extends StatelessWidget {
  const AdminFinancialOperationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Finansal İşlemler'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Ödemeler'),
              Tab(text: 'İadeler'),
              Tab(text: 'Kasa Oturumları'),
              Tab(text: 'Fiskal Günlük'),
              Tab(text: 'Offline Yetkiler'),
            ],
          ),
        ),
        body: const SafeArea(
          child: TabBarView(
            children: [
              _PaymentSessionsTab(),
              _RefundsTab(),
              _CashSessionsTab(),
              _FiscalJournalTab(),
              _OfflineLeasesTab(),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentSessionsTab extends ConsumerWidget {
  const _PaymentSessionsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminPaymentSessionsProvider(50));
    return async.when(
      loading: () =>
          const LoadingView(message: 'Ödeme oturumları yükleniyor...'),
      error: (error, stack) => ErrorView(
        message: 'Ödeme oturumları yüklenemedi.',
        retryLabel: 'Tekrar dene',
        onRetry: () => ref.invalidate(adminPaymentSessionsProvider),
      ),
      data: (sessions) {
        if (sessions.isEmpty) {
          return const EmptyView(
            icon: Icons.payments_outlined,
            message: 'Bu şubede henüz bir ödeme oturumu yok.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(adminPaymentSessionsProvider),
          child: ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: sessions.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final s = sessions[index];
              final currency = _currencyFor(s.currencyCode);
              return AppCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Icon(Icons.circle,
                        size: 10, color: _paymentStatusColor(s.status)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Çek: ${s.checkId}',
                              style: AppTypography.bodyMedium),
                          Text(_formatDate(s.createdAt),
                              style: AppTypography.bodySmall
                                  .copyWith(color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                            '${Money(s.settledAmountMinorUnits, currency)} / '
                            '${Money(s.payableAmountMinorUnits, currency)}',
                            style: AppTypography.bodyMedium),
                        Text(_paymentStatusLabel(s.status),
                            style: AppTypography.bodySmall.copyWith(
                                color: _paymentStatusColor(s.status))),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _RefundsTab extends ConsumerWidget {
  const _RefundsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminRefundsProvider(50));
    return async.when(
      loading: () => const LoadingView(message: 'İadeler yükleniyor...'),
      error: (error, stack) => ErrorView(
        message: 'İadeler yüklenemedi.',
        retryLabel: 'Tekrar dene',
        onRetry: () => ref.invalidate(adminRefundsProvider),
      ),
      data: (refunds) {
        if (refunds.isEmpty) {
          return const EmptyView(
            icon: Icons.assignment_return_outlined,
            message: 'Bu şubede henüz bir iade kaydı yok.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(adminRefundsProvider),
          child: ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: refunds.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final r = refunds[index];
              return AppCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Icon(Icons.circle,
                        size: 10, color: _refundStatusColor(r.status)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              'Çek: ${r.checkId} — ${_refundTypeLabel(r.refundType)}',
                              style: AppTypography.bodyMedium),
                          Text(_formatDate(r.createdAt),
                              style: AppTypography.bodySmall
                                  .copyWith(color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    Text(_refundStatusLabel(r.status),
                        style: AppTypography.bodySmall
                            .copyWith(color: _refundStatusColor(r.status))),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _CashSessionsTab extends ConsumerWidget {
  const _CashSessionsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminCashSessionsProvider(50));
    return async.when(
      loading: () =>
          const LoadingView(message: 'Kasa oturumları yükleniyor...'),
      error: (error, stack) => ErrorView(
        message: 'Kasa oturumları yüklenemedi.',
        retryLabel: 'Tekrar dene',
        onRetry: () => ref.invalidate(adminCashSessionsProvider),
      ),
      data: (sessions) {
        if (sessions.isEmpty) {
          return const EmptyView(
            icon: Icons.point_of_sale_outlined,
            message: 'Bu şubede henüz bir kasa oturumu yok.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(adminCashSessionsProvider),
          child: ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: sessions.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final s = sessions[index];
              final currency = _currencyFor(s.currencyCode);
              return AppCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Icon(Icons.circle,
                        size: 10, color: _cashSessionStatusColor(s.status)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Çekmece: ${s.drawerId}',
                              style: AppTypography.bodyMedium),
                          Text(
                              '${s.businessDate} · ${_formatDate(s.createdAt)}',
                              style: AppTypography.bodySmall
                                  .copyWith(color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${Money(s.settledAmountMinorUnits, currency)}',
                            style: AppTypography.bodyMedium),
                        Text(_cashSessionStatusLabel(s.status),
                            style: AppTypography.bodySmall.copyWith(
                                color: _cashSessionStatusColor(s.status))),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _FiscalJournalTab extends ConsumerStatefulWidget {
  const _FiscalJournalTab();

  @override
  ConsumerState<_FiscalJournalTab> createState() => _FiscalJournalTabState();
}

class _FiscalJournalTabState extends ConsumerState<_FiscalJournalTab> {
  bool _onlyUnresolved = false;

  @override
  Widget build(BuildContext context) {
    final query = AdminFiscalJournalQuery(onlyUnresolved: _onlyUnresolved);
    final async = ref.watch(adminFiscalOperationsProvider(query));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          child: Row(
            children: [
              const Text('Sadece çözülmemiş', style: AppTypography.bodyMedium),
              const Spacer(),
              Switch(
                value: _onlyUnresolved,
                onChanged: (value) => setState(() => _onlyUnresolved = value),
              ),
            ],
          ),
        ),
        Expanded(
          child: async.when(
            loading: () =>
                const LoadingView(message: 'Fiskal günlük yükleniyor...'),
            error: (error, stack) => ErrorView(
              message: 'Fiskal günlük yüklenemedi.',
              retryLabel: 'Tekrar dene',
              onRetry: () => ref.invalidate(adminFiscalOperationsProvider),
            ),
            data: (entries) {
              if (entries.isEmpty) {
                return EmptyView(
                  icon: Icons.receipt_long_outlined,
                  message: _onlyUnresolved
                      ? 'Çözüm bekleyen fiskal işlem yok.'
                      : 'Bu şubede henüz bir fiskal işlem yok.',
                );
              }
              return RefreshIndicator(
                onRefresh: () async =>
                    ref.invalidate(adminFiscalOperationsProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: entries.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final e = entries[index];
                    final currency = _currencyFor(e.currencyCode);
                    return AppCard(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Row(
                        children: [
                          Icon(Icons.circle,
                              size: 10, color: _fiscalStatusColor(e.status)),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_fiscalOperationTypeLabel(e.operationType),
                                    style: AppTypography.bodyMedium),
                                Text(_formatDate(e.createdAt),
                                    style: AppTypography.bodySmall.copyWith(
                                        color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('${Money(e.amountMinorUnits, currency)}',
                                  style: AppTypography.bodyMedium),
                              Text(_fiscalStatusLabel(e.status),
                                  style: AppTypography.bodySmall.copyWith(
                                      color: _fiscalStatusColor(e.status))),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _OfflineLeasesTab extends ConsumerWidget {
  const _OfflineLeasesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminOfflineLeasesProvider(50));
    return async.when(
      loading: () =>
          const LoadingView(message: 'Offline yetkiler yükleniyor...'),
      error: (error, stack) => ErrorView(
        message: 'Offline yetkiler yüklenemedi.',
        retryLabel: 'Tekrar dene',
        onRetry: () => ref.invalidate(adminOfflineLeasesProvider),
      ),
      data: (leases) {
        if (leases.isEmpty) {
          return const EmptyView(
            icon: Icons.wifi_off_outlined,
            message: 'Bu şubede henüz bir offline yetki kaydı yok.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(adminOfflineLeasesProvider),
          child: ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: leases.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final l = leases[index];
              final statusColor = l.revoked
                  ? AppColors.error
                  : (l.isExpired ? AppColors.warning : AppColors.success);
              final statusLabel = l.revoked
                  ? 'İptal Edildi'
                  : (l.isExpired ? 'Süresi Doldu' : 'Aktif');
              return AppCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Icon(Icons.circle, size: 10, color: statusColor),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Cihaz: ${l.deviceId}',
                              style: AppTypography.bodyMedium),
                          Text(
                              '${l.transactionsUsed}/${l.maxTransactionCount} işlem · '
                              'bitiş ${_formatDate(l.expiresAt)}',
                              style: AppTypography.bodySmall
                                  .copyWith(color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    Text(statusLabel,
                        style: AppTypography.bodySmall
                            .copyWith(color: statusColor)),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

Color _paymentStatusColor(String status) {
  switch (status) {
    case 'completed':
      return AppColors.success;
    case 'cancelled':
      return AppColors.error;
    default:
      return AppColors.warning;
  }
}

String _paymentStatusLabel(String status) {
  switch (status) {
    case 'open':
      return 'Açık';
    case 'completed':
      return 'Tamamlandı';
    case 'cancelled':
      return 'İptal';
    default:
      return status;
  }
}

Color _refundStatusColor(String status) {
  switch (status) {
    case 'completed':
      return AppColors.success;
    case 'rejected':
    case 'failed':
      return AppColors.error;
    default:
      return AppColors.warning;
  }
}

String _refundStatusLabel(String status) {
  switch (status) {
    case 'pendingApproval':
      return 'Onay Bekliyor';
    case 'approved':
      return 'Onaylandı';
    case 'completed':
      return 'Tamamlandı';
    case 'rejected':
      return 'Reddedildi';
    case 'failed':
      return 'Başarısız';
    default:
      return status;
  }
}

String _refundTypeLabel(String type) {
  switch (type) {
    case 'full':
      return 'Tam İade';
    case 'partial':
      return 'Kısmi İade';
    default:
      return type;
  }
}

Color _cashSessionStatusColor(String status) {
  switch (status) {
    case 'active':
      return AppColors.success;
    case 'rejected':
    case 'openRejected':
      return AppColors.error;
    case 'closed':
      return AppColors.textSecondary;
    default:
      return AppColors.warning;
  }
}

String _cashSessionStatusLabel(String status) {
  switch (status) {
    case 'awaitingOpenApproval':
      return 'Açılış Onayı Bekliyor';
    case 'openRejected':
      return 'Açılış Reddedildi';
    case 'active':
      return 'Aktif';
    case 'pendingApproval':
      return 'Onay Bekliyor';
    case 'approved':
      return 'Onaylandı';
    case 'rejected':
      return 'Reddedildi';
    case 'closed':
      return 'Kapalı';
    default:
      return status;
  }
}

Color _fiscalStatusColor(String status) {
  switch (status) {
    case 'succeeded':
      return AppColors.success;
    case 'failed':
    case 'rejected':
      return AppColors.error;
    case 'timedOut':
    case 'unknownReconciliationRequired':
    case 'manualInterventionRequired':
      return AppColors.warning;
    default:
      return AppColors.textSecondary;
  }
}

String _fiscalStatusLabel(String status) {
  switch (status) {
    case 'pending':
      return 'Beklemede';
    case 'succeeded':
      return 'Başarılı';
    case 'failed':
      return 'Başarısız';
    case 'timedOut':
      return 'Zaman Aşımı — Sonuç Bilinmiyor';
    case 'unknownReconciliationRequired':
      return 'Sonuç Bilinmiyor — Mutabakat Gerekli';
    case 'manualInterventionRequired':
      return 'Manuel Müdahale Gerekli';
    default:
      return status;
  }
}

String _fiscalOperationTypeLabel(String type) {
  switch (type) {
    case 'sale':
      return 'Satış Fişi';
    case 'refund':
      return 'İade Fişi';
    default:
      return type;
  }
}
