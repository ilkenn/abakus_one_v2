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
import '../../data/platform_customer_directory_gateway.dart';
import '../providers/platform_dependencies_provider.dart';

const List<(String, String)> _platformRestrictionReasonCodes = [
  ('policyViolation', 'Platform Kural İhlali'),
  ('fraudSuspected', 'Şüpheli İşlem'),
  ('legalHold', 'Hukuki Talep'),
  ('platformOwnerDecision', 'Platform Sahibi Kararı'),
];

/// Platform-wide customer detail — AP-3 continuation (`docs/decisions.md`
/// ADR-039). Global identity, tenant relationship summary, capability-gated
/// restriction, and the ONE path to a full saved-address-book reveal
/// (mandatory reason, always server-audited).
class PlatformCustomerDetailScreen extends ConsumerStatefulWidget {
  const PlatformCustomerDetailScreen({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<PlatformCustomerDetailScreen> createState() =>
      _PlatformCustomerDetailScreenState();
}

class _PlatformCustomerDetailScreenState
    extends ConsumerState<PlatformCustomerDetailScreen> {
  PlatformCustomerDetail? _detail;
  Object? _error;
  bool _mutating = false;
  String? _mutationError;
  List<Map<String, dynamic>>? _revealedAddresses;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _detail = null;
      _error = null;
    });
    try {
      final detail = await ref
          .read(platformCustomerDirectoryGatewayProvider)
          .getDetail(widget.uid);
      if (!mounted) return;
      setState(() => _detail = detail);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  Future<void> _toggleRestriction(PlatformCustomerDetail detail) async {
    final restrict = !detail.isRestricted;
    final result = await showDialog<({String reasonCode, String reasonMessage})>(
      context: context,
      builder: (dialogContext) =>
          _PlatformRestrictionReasonDialog(restrict: restrict),
    );
    if (result == null) return;

    setState(() {
      _mutating = true;
      _mutationError = null;
    });
    try {
      await ref.read(platformCustomerDirectoryGatewayProvider).setRestriction(
            uid: widget.uid,
            restrict: restrict,
            reasonCode: result.reasonCode,
            reasonMessage: result.reasonMessage,
          );
      if (!mounted) return;
      await _load();
    } on PlatformCustomerDirectoryException catch (e) {
      if (!mounted) return;
      setState(() => _mutationError = e.message);
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _revealAddressBook() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => const _RevealAddressBookReasonDialog(),
    );
    if (reason == null || reason.trim().isEmpty) return;

    setState(() {
      _mutating = true;
      _mutationError = null;
    });
    try {
      final addresses = await ref
          .read(platformCustomerDirectoryGatewayProvider)
          .revealFullAddressBook(uid: widget.uid, reason: reason.trim());
      if (!mounted) return;
      setState(() => _revealedAddresses = addresses);
    } on PlatformCustomerDirectoryException catch (e) {
      if (!mounted) return;
      setState(() => _mutationError = e.message);
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_detail?.displayName ?? 'Müşteri'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final error = _error;
    final detail = _detail;
    if (error != null) {
      final isPermissionDenied = error is PlatformCustomerDirectoryException &&
          error.code == 'permission-denied';
      final isNotFound = error is PlatformCustomerDirectoryException &&
          error.code == 'not-found';
      if (isNotFound) {
        return const EmptyView(
          icon: Icons.person_off_outlined,
          message: 'Bu müşteri bulunamadı.',
        );
      }
      return ErrorView(
        message: isPermissionDenied
            ? 'Bu müşterinin bilgilerini görüntüleme yetkiniz yok.'
            : 'Müşteri bilgisi yüklenirken bir sorun oluştu.',
        retryLabel: 'Tekrar Dene',
        onRetry: _load,
      );
    }
    if (detail == null) {
      return const LoadingView(message: 'Müşteri bilgisi yükleniyor...');
    }
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
                label: 'İlişkili Kiracılar',
                value: detail.relatedOrganizationIds.isEmpty
                    ? 'Yok (kiracısız kayıt)'
                    : detail.relatedOrganizationIds.join(', '),
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
                  Expanded(
                    child: Text(
                      detail.isRestricted
                          ? 'Platform genelinde kısıtlı${detail.restrictionReasonMessage != null ? ' — ${detail.restrictionReasonMessage}' : ''}'
                          : 'Aktif',
                      style: AppTypography.bodyMedium.copyWith(
                        color: detail.isRestricted
                            ? AppColors.error
                            : AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
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
                child: Text(
                  detail.isRestricted
                      ? 'Platform Kısıtlamasını Kaldır'
                      : 'Platform Genelinde Kısıtla',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tam Adres Defteri', style: AppTypography.labelLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Yalnızca gerekçe girilerek görüntülenebilir; her görüntüleme '
                'denetim kaydına işlenir.',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_revealedAddresses == null)
                OutlinedButton.icon(
                  onPressed: _mutating ? null : _revealAddressBook,
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Adres Defterini Göster'),
                )
              else if (_revealedAddresses!.isEmpty)
                Text(
                  'Kayıtlı adres yok.',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                )
              else
                for (final address in _revealedAddresses!)
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
            width: 150,
            child: Text(
              label,
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
          ),
          Expanded(child: Text(value, style: AppTypography.bodyMedium)),
        ],
      ),
    );
  }
}

class _PlatformRestrictionReasonDialog extends StatefulWidget {
  final bool restrict;

  const _PlatformRestrictionReasonDialog({required this.restrict});

  @override
  State<_PlatformRestrictionReasonDialog> createState() =>
      _PlatformRestrictionReasonDialogState();
}

class _PlatformRestrictionReasonDialogState
    extends State<_PlatformRestrictionReasonDialog> {
  String _reasonCode = _platformRestrictionReasonCodes.first.$1;
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
        widget.restrict
            ? 'Platform Genelinde Kısıtla'
            : 'Platform Kısıtlamasını Kaldır',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.restrict) ...[
            DropdownButtonFormField<String>(
              key: const Key('platformRestrictionReasonCodeDropdown'),
              initialValue: _reasonCode,
              decoration: const InputDecoration(labelText: 'Neden Kodu'),
              items: [
                for (final (code, label) in _platformRestrictionReasonCodes)
                  DropdownMenuItem(value: code, child: Text(label)),
              ],
              onChanged: (value) =>
                  setState(() => _reasonCode = value ?? _reasonCode),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          TextField(
            key: const Key('platformRestrictionReasonMessageField'),
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
              reasonCode:
                  widget.restrict ? _reasonCode : 'platformOwnerDecision',
              reasonMessage: message,
            ));
          },
          child: const Text('Onayla'),
        ),
      ],
    );
  }
}

class _RevealAddressBookReasonDialog extends StatefulWidget {
  const _RevealAddressBookReasonDialog();

  @override
  State<_RevealAddressBookReasonDialog> createState() =>
      _RevealAddressBookReasonDialogState();
}

class _RevealAddressBookReasonDialogState
    extends State<_RevealAddressBookReasonDialog> {
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.kLarge),
      title: const Text('Adres Defterini Görüntüleme Gerekçesi'),
      content: TextField(
        key: const Key('revealAddressBookReasonField'),
        controller: _reasonController,
        decoration: const InputDecoration(labelText: 'Gerekçe'),
        maxLines: 2,
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        ElevatedButton(
          onPressed: () {
            final reason = _reasonController.text.trim();
            if (reason.isEmpty) return;
            Navigator.of(context).pop(reason);
          },
          child: const Text('Görüntüle'),
        ),
      ],
    );
  }
}

String _formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
