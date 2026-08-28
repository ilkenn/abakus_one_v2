import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../data/tenant_customer_directory_gateway.dart';
import '../providers/admin_dependencies_provider.dart';
import '../providers/tenant_customer_detail_provider.dart';

const List<(String, String)> _restrictionReasonCodes = [
  ('policyViolation', 'Kural İhlali'),
  ('fraudSuspected', 'Şüpheli İşlem'),
  ('paymentIssue', 'Ödeme Sorunu'),
  ('staffDecision', 'Personel Kararı'),
];

/// Customer 360 — AP-3 continuation (`docs/decisions.md` ADR-039). Rewired
/// onto the real tenant Customer Directory backend
/// (`getTenantCustomerDetail`/`setTenantCustomerRestriction`), replacing
/// the previous in-memory `CustomerRepository` lookup.
///
/// **Visit history, feedback tickets, and staff notes sections were
/// removed by this rewire, not silently forgotten**: those three panels
/// were keyed by the legacy in-memory `Customer.id` — an entirely
/// different, unrelated identifier space from the real tenant directory's
/// `customerId` (a genuine Firebase Auth uid). Querying the old
/// CRM/feedback/notes repositories with the new real customer's id would
/// silently return empty or, worse, coincidentally wrong data, not a
/// meaningful "no data yet" state — so this rewire drops those three
/// panels entirely rather than show data that structurally cannot
/// correspond to the customer on screen. The old `CustomerRepository`,
/// `CustomerVisit`, `CustomerFeedback`, and `CustomerAdminNote`
/// repositories/screens are untouched and still exist — this is a scope
/// change to THIS screen only, not a deletion of that code.
class CustomerDetailScreen extends ConsumerStatefulWidget {
  const CustomerDetailScreen({
    super.key,
    required this.customerId,
    required this.organizationId,
  });

  final String customerId;
  final String organizationId;

  @override
  ConsumerState<CustomerDetailScreen> createState() =>
      _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends ConsumerState<CustomerDetailScreen> {
  bool _mutating = false;
  String? _mutationError;

  ({String organizationId, String customerId}) get _args =>
      (organizationId: widget.organizationId, customerId: widget.customerId);

  Future<void> _toggleRestriction(TenantCustomerDetail detail) async {
    final restrict = !detail.isRestricted;
    final result =
        await showDialog<({String reasonCode, String reasonMessage})>(
      context: context,
      builder: (dialogContext) => _RestrictionReasonDialog(restrict: restrict),
    );
    if (result == null) return;

    setState(() {
      _mutating = true;
      _mutationError = null;
    });
    try {
      await ref.read(tenantCustomerDirectoryGatewayProvider).setRestriction(
            organizationId: widget.organizationId,
            customerId: widget.customerId,
            restrict: restrict,
            reasonCode: result.reasonCode,
            reasonMessage: result.reasonMessage,
          );
      if (!mounted) return;
      ref.invalidate(tenantCustomerDetailProvider(_args));
    } on TenantCustomerDirectoryException catch (e) {
      if (!mounted) return;
      setState(() => _mutationError = e.message);
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(tenantCustomerDetailProvider(_args));
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          detailAsync.valueOrNull?.displayName ?? 'Müşteri',
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: detailAsync.when(
          loading: () =>
              const LoadingView(message: 'Müşteri bilgisi yükleniyor...'),
          error: (error, stackTrace) {
            final isPermissionDenied =
                error is TenantCustomerDirectoryException &&
                    error.code == 'permission-denied';
            final isNotFound = error is TenantCustomerDirectoryException &&
                error.code == 'not-found';
            if (isNotFound) {
              return const EmptyView(
                icon: Icons.person_off_outlined,
                message: 'Bu müşteri bu şubede bulunamadı.',
              );
            }
            return ErrorView(
              message: isPermissionDenied
                  ? 'Bu müşterinin bilgilerini görüntüleme yetkiniz yok.'
                  : 'Müşteri bilgisi yüklenirken bir sorun oluştu.',
              retryLabel: 'Tekrar Dene',
              onRetry: () =>
                  ref.invalidate(tenantCustomerDetailProvider(_args)),
            );
          },
          data: (detail) => _buildBody(detail),
        ),
      ),
    );
  }

  Widget _buildBody(TenantCustomerDetail detail) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (_mutationError != null) ...[
          Text(_mutationError!,
              style: AppTypography.bodySmall.copyWith(color: AppColors.error)),
          const SizedBox(height: AppSpacing.sm),
        ],
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow(label: 'Telefon', value: detail.phoneMasked),
              _DetailRow(
                label: 'Kayıt Tarihi',
                value: _formatDate(detail.registrationDate),
              ),
              _DetailRow(
                label: 'Son Aktivite',
                value: _formatDate(detail.lastActivityAt),
              ),
              _DetailRow(
                label: 'Toplam Sipariş',
                value: '${detail.totalOrderCount}',
              ),
              _DetailRow(
                label: 'Son Sipariş',
                value: detail.lastOrderAt == null
                    ? 'Henüz sipariş yok'
                    : _formatDate(detail.lastOrderAt!),
              ),
              _DetailRow(
                label: 'Şubeler',
                value: detail.relatedBranchIds.isEmpty
                    ? 'Kayıt yok'
                    : detail.relatedBranchIds.join(', '),
              ),
              _DetailRow(
                label: 'Pazarlama İzni',
                value: detail.marketingConsent == 'notCaptured'
                    ? 'Alınmadı'
                    : detail.marketingConsent,
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Icon(
                    detail.isRestricted
                        ? Icons.block_rounded
                        : Icons.check_circle_outline,
                    size: 18,
                    color: detail.isRestricted
                        ? AppColors.error
                        : AppColors.primary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    detail.isRestricted
                        ? 'Hesap kısıtlı${detail.restrictionReasonMessage != null ? ' — ${detail.restrictionReasonMessage}' : ''}'
                        : 'Hesap aktif',
                    style: AppTypography.bodyMedium.copyWith(
                      color: detail.isRestricted
                          ? AppColors.error
                          : AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                onPressed: _mutating ? null : () => _toggleRestriction(detail),
                style: OutlinedButton.styleFrom(
                  foregroundColor:
                      detail.isRestricted ? AppColors.primary : AppColors.error,
                ),
                child: _mutating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        detail.isRestricted
                            ? 'Kısıtlamayı Kaldır'
                            : 'Hesabı Kısıtla',
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Teslimat Adresleri (${detail.orderAddressSnapshots.length})',
          style: AppTypography.labelLarge,
        ),
        const SizedBox(height: AppSpacing.xs),
        if (detail.orderAddressSnapshots.isEmpty)
          Text(
            'Bu şubedeki siparişlerinde kayıtlı bir teslimat adresi yok.',
            style: AppTypography.bodySmall
                .copyWith(color: AppColors.textSecondary),
          )
        else
          for (final address in detail.orderAddressSnapshots)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                [
                  address['label'],
                  address['line1'],
                  address['city'],
                ].whereType<String>().join(' · '),
                style: AppTypography.bodySmall,
              ),
            ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(value, style: AppTypography.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _RestrictionReasonDialog extends StatefulWidget {
  final bool restrict;

  const _RestrictionReasonDialog({required this.restrict});

  @override
  State<_RestrictionReasonDialog> createState() =>
      _RestrictionReasonDialogState();
}

class _RestrictionReasonDialogState extends State<_RestrictionReasonDialog> {
  String _reasonCode = _restrictionReasonCodes.first.$1;
  final _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.kLarge),
      title: Text(
        widget.restrict ? 'Hesabı Kısıtla' : 'Kısıtlamayı Kaldır',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.restrict) ...[
            DropdownButtonFormField<String>(
              key: const Key('restrictionReasonCodeDropdown'),
              initialValue: _reasonCode,
              decoration: const InputDecoration(labelText: 'Neden Kodu'),
              items: [
                for (final (code, label) in _restrictionReasonCodes)
                  DropdownMenuItem(value: code, child: Text(label)),
              ],
              onChanged: (value) =>
                  setState(() => _reasonCode = value ?? _reasonCode),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          TextField(
            key: const Key('restrictionReasonMessageField'),
            controller: _messageController,
            decoration: const InputDecoration(labelText: 'Açıklama'),
            maxLines: 2,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        ElevatedButton(
          onPressed: () {
            final message = _messageController.text.trim();
            if (message.isEmpty) return;
            Navigator.of(context).pop((
              reasonCode: widget.restrict ? _reasonCode : 'staffDecision',
              reasonMessage: message,
            ));
          },
          child: const Text('Onayla'),
        ),
      ],
    );
  }
}

String _formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
