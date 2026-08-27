import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../courier/presentation/providers/courier_core_dependencies_provider.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/presentation/providers/kds_dependencies_provider.dart';
import '../../application/use_cases/register_device.dart';
import '../../application/use_cases/set_admin_device_status.dart';
import '../../application/use_cases/set_source_device_active.dart';
import '../../data/trusted_device_gateway.dart';
import '../../domain/device/admin_device_registration_status.dart';
import '../../domain/device/device_registry_entry.dart';
import '../../domain/device/device_type.dart';
import '../../domain/trusted_device/trusted_device.dart';
import '../providers/admin_dependencies_provider.dart';
import 'approval_inbox_screen.dart';

const _deviceTypeLabels = {
  DeviceType.kitchenDisplay: 'Mutfak Ekranı (KDS)',
  DeviceType.courierDevice: 'Kurye Cihazı',
  DeviceType.posTerminal: 'POS Terminali',
  DeviceType.printer: 'Yazıcı',
  DeviceType.paymentTerminal: 'Ödeme Terminali',
};

/// Registerable device types have no other owning aggregate — see
/// `RegisterDevice`'s own doc comment.
const _registerableTypes = [
  DeviceType.posTerminal,
  DeviceType.printer,
  DeviceType.paymentTerminal,
];

/// Two genuinely distinct device concepts share this one Admin nav
/// destination — disclosed explicitly, not silently merged:
///
/// - **Tab 1, "Cihaz Envanteri"** — the pre-existing unified device
///   registry (Phase 6L, `docs/decisions.md` ADR-023): POS terminal/
///   printer/payment-terminal placeholders plus read/toggle-only
///   projections of KDS/courier devices. Entirely in-memory — unchanged by
///   AP-2's final wiring pass, still demo data.
/// - **Tab 2, "Güvenilir Cihazlar"** — AP-2's real trusted-device identity/
///   session backend (`trustedDeviceRegistrations`, Ed25519/RSA-SHA256
///   challenge-response). Genuinely wired this pass: a live Firestore
///   stream of the branch's real device roster, and real
///   suspend/revoke/retire mutations. A device's own *registration* and
///   *activation* never happen from this screen — registration is
///   performed by the physical device itself during onboarding, and
///   activation only ever happens through the Approval Inbox (never a
///   direct client mutation) — this tab is the roster + lifecycle-action
///   surface, not the activation surface.
class DeviceRegistryScreen extends ConsumerStatefulWidget {
  const DeviceRegistryScreen({
    super.key,
    required this.branchId,
    this.authorizationPolicy,
    this.performedByStaffId = '',
  });

  final String branchId;
  final PosAuthorizationPolicy? authorizationPolicy;
  final String performedByStaffId;

  @override
  ConsumerState<DeviceRegistryScreen> createState() =>
      _DeviceRegistryScreenState();
}

class _DeviceRegistryScreenState extends ConsumerState<DeviceRegistryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  List<DeviceRegistryEntry>? _entries;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final entries = await ref
        .read(buildDeviceRegistryProjectionProvider)
        .call(branchId: widget.branchId);
    if (!mounted) return;
    setState(() => _entries = entries);
  }

  bool _requirePolicy(void Function(PosAuthorizationPolicy policy) run) {
    final policy = widget.authorizationPolicy;
    if (policy == null) {
      setState(() => _error = 'Yetki politikası tanımlı değil.');
      return false;
    }
    run(policy);
    return true;
  }

  Future<void> _toggleSourceDeviceActive(DeviceRegistryEntry entry) async {
    _requirePolicy((policy) async {
      try {
        await SetSourceDeviceActive(
          authorizationPolicy: policy,
          kitchenDisplayDeviceRepository:
              ref.read(kitchenDisplayDeviceRepositoryProvider),
          courierDeviceRepository: ref.read(courierDeviceRepositoryProvider),
          auditRepository: ref.read(adminAuditEntryRepositoryProvider),
        )(
          type: entry.type,
          deviceId: entry.id,
          isActive: !entry.isActive,
          branchId: entry.branchId,
          performedByStaffId: widget.performedByStaffId,
          performedAt: DateTime.now(),
        );
        setState(() => _error = null);
        await _load();
      } catch (e) {
        setState(() => _error = e.toString());
      }
    });
  }

  Future<void> _setAdminDeviceStatus(
    DeviceRegistryEntry entry,
    AdminDeviceRegistrationStatus status,
  ) async {
    _requirePolicy((policy) async {
      try {
        await SetAdminDeviceStatus(
          authorizationPolicy: policy,
          repository: ref.read(adminDeviceRegistrationRepositoryProvider),
          auditRepository: ref.read(adminAuditEntryRepositoryProvider),
        )(
          deviceId: entry.id,
          newStatus: status,
          performedByStaffId: widget.performedByStaffId,
          performedAt: DateTime.now(),
        );
        setState(() => _error = null);
        await _load();
      } catch (e) {
        setState(() => _error = e.toString());
      }
    });
  }

  Future<void> _register() async {
    final labelController = TextEditingController();
    var selectedType = _registerableTypes.first;
    final result = await showDialog<(DeviceType, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Cihaz Kaydet'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButton<DeviceType>(
                value: selectedType,
                items: [
                  for (final type in _registerableTypes)
                    DropdownMenuItem(
                      value: type,
                      child: Text(_deviceTypeLabels[type]!),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => selectedType = value);
                  }
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: labelController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Etiket / Ad'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context)
                  .pop((selectedType, labelController.text)),
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
    if (result == null || result.$2.trim().isEmpty) return;

    _requirePolicy((policy) async {
      try {
        await RegisterDevice(
          authorizationPolicy: policy,
          idGenerator: ref.read(adminDeviceRegistrationIdGeneratorProvider),
          repository: ref.read(adminDeviceRegistrationRepositoryProvider),
          auditRepository: ref.read(adminAuditEntryRepositoryProvider),
        )(
          type: result.$1,
          branchId: widget.branchId,
          label: result.$2.trim(),
          performedByStaffId: widget.performedByStaffId,
          registeredAt: DateTime.now(),
        );
        setState(() => _error = null);
        await _load();
      } catch (e) {
        setState(() => _error = e.toString());
      }
    });
  }

  bool _isSourceOwned(DeviceType type) =>
      type == DeviceType.kitchenDisplay || type == DeviceType.courierDevice;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Cihazlar'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          if (_tabController.index == 0)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Cihaz Kaydet',
              onPressed: _register,
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Cihaz Envanteri'),
            Tab(text: 'Güvenilir Cihazlar'),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildInventoryTab(),
            _TrustedDevicesTab(branchId: widget.branchId),
          ],
        ),
      ),
    );
  }

  Widget _buildInventoryTab() {
    final entries = _entries;
    return entries == null
        ? const LoadingView(message: 'Cihazlar yükleniyor...')
        : entries.isEmpty
            ? const EmptyView(
                icon: Icons.devices_outlined,
                message: 'Bu şube için kayıtlı cihaz yok.',
              )
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  const _DemoDataBanner(
                    message: 'Bu envanter demo verisiyle çalışır — gerçek bir '
                        'backend\'e bağlı değildir.',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (_error != null) ...[
                    Text(_error!,
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.error)),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  for (final entry in entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: AppCard(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(entry.label,
                                      style: AppTypography.titleMedium),
                                ),
                                Icon(
                                  entry.isArchived
                                      ? Icons.archive_outlined
                                      : entry.isActive
                                          ? Icons.check_circle_outline
                                          : Icons.pause_circle_outline,
                                  color: entry.isArchived
                                      ? AppColors.textSecondary
                                      : entry.isActive
                                          ? AppColors.success
                                          : AppColors.error,
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              '${_deviceTypeLabels[entry.type]} · '
                              '${entry.isArchived ? 'arşivlendi' : entry.isActive ? 'aktif' : 'pasif'}'
                              '${entry.softwareVersion != null ? ' · sürüm ${entry.softwareVersion}' : ''}',
                              style: AppTypography.bodySmall
                                  .copyWith(color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Wrap(
                              spacing: AppSpacing.sm,
                              children: [
                                if (_isSourceOwned(entry.type))
                                  OutlinedButton(
                                    onPressed: () =>
                                        _toggleSourceDeviceActive(entry),
                                    child: Text(entry.isActive
                                        ? 'Pasifleştir'
                                        : 'Aktifleştir'),
                                  )
                                else ...[
                                  if (!entry.isArchived) ...[
                                    if (!entry.isActive)
                                      OutlinedButton(
                                        onPressed: () => _setAdminDeviceStatus(
                                            entry,
                                            AdminDeviceRegistrationStatus
                                                .active),
                                        child: const Text('Aktifleştir'),
                                      ),
                                    if (entry.isActive)
                                      OutlinedButton(
                                        onPressed: () => _setAdminDeviceStatus(
                                            entry,
                                            AdminDeviceRegistrationStatus
                                                .inactive),
                                        child: const Text('Pasifleştir '
                                            '(Kaldır)'),
                                      ),
                                    OutlinedButton(
                                      onPressed: () => _setAdminDeviceStatus(
                                          entry,
                                          AdminDeviceRegistrationStatus
                                              .archived),
                                      child: const Text('Arşivle'),
                                    ),
                                  ],
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
  }
}

class _DemoDataBanner extends StatelessWidget {
  const _DemoDataBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warning),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.warning),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodySmall.copyWith(color: AppColors.warning),
            ),
          ),
        ],
      ),
    );
  }
}

const _statusLabels = {
  TrustedDeviceStatus.pending: 'Onay Bekliyor',
  TrustedDeviceStatus.active: 'Aktif',
  TrustedDeviceStatus.suspended: 'Askıya Alındı',
  TrustedDeviceStatus.revoked: 'İptal Edildi',
  TrustedDeviceStatus.retired: 'Emekliye Ayrıldı',
};

const _trustTierLabels = {
  TrustedDeviceTrustTier.hardwareAttested: 'Donanım Onaylı',
  TrustedDeviceTrustTier.platformProtected: 'Platform Korumalı',
  TrustedDeviceTrustTier.unsupportedOrUntrusted: 'Desteklenmiyor',
};

const _capabilityLabels = {
  TrustedDeviceCapability.pos: 'POS',
  TrustedDeviceCapability.kds: 'KDS',
  TrustedDeviceCapability.printerController: 'Yazıcı Kontrolcüsü',
};

const _platformLabels = {
  TrustedDevicePlatform.android: 'Android',
  TrustedDevicePlatform.ios: 'iOS',
  TrustedDevicePlatform.windows: 'Windows',
  TrustedDevicePlatform.macos: 'macOS',
  TrustedDevicePlatform.web: 'Web',
};

/// The real trusted-device tab — a live Firestore stream of the branch's
/// device roster plus real suspend/revoke/retire actions. No public key,
/// challenge, nonce, or session id is ever read or rendered here — the
/// domain model this consumes structurally has no such field
/// (`TrustedDevice`'s own doc comment).
class _TrustedDevicesTab extends ConsumerWidget {
  const _TrustedDevicesTab({required this.branchId});

  final String branchId;

  Future<void> _confirmAndAct(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String actionLabel,
    required Future<void> Function(String reason) action,
  }) async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: reasonController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Gerekçe (zorunlu)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            // Deliberately not disabled based on the controller's current
            // text — a plain `TextField` inside a non-`StatefulBuilder`
            // dialog never rebuilds on keystrokes, so a disabled-while-
            // empty button here would stay permanently disabled even
            // after real text is typed. Blank/whitespace-only input is
            // instead rejected right after the dialog closes, below.
            onPressed: () =>
                Navigator.of(context).pop(reasonController.text.trim()),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;
    try {
      await action(reason);
    } on TrustedDeviceException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final organizationId = ref.watch(currentOrganizationIdProvider);
    final devicesAsync = ref.watch(_devicesStreamProvider(
        (organizationId: organizationId, branchId: branchId)));

    return devicesAsync.when(
      loading: () =>
          const LoadingView(message: 'Güvenilir cihazlar yükleniyor...'),
      error: (error, stackTrace) => ErrorView(
        message: 'Cihaz backend\'ine ulaşılamadı.',
        retryLabel: 'Tekrar Dene',
        onRetry: () => ref.invalidate(_devicesStreamProvider(
            (organizationId: organizationId, branchId: branchId))),
      ),
      data: (devices) {
        if (devices.isEmpty) {
          return const EmptyView(
            icon: Icons.verified_user_outlined,
            message: 'Bu şube için kayıtlı güvenilir cihaz yok. Yeni bir '
                'cihaz kaydı, Onay Kutusu\'nda görünecektir.',
          );
        }
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            for (final device in devices)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: AppCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '${_platformLabels[device.platform]} · '
                              '${device.deviceId.substring(0, 8)}…',
                              style: AppTypography.titleMedium,
                            ),
                          ),
                          _StatusChip(status: device.status),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '${_trustTierLabels[device.trustTier]} · '
                        '${device.capabilities.map((c) => _capabilityLabels[c]).join(', ')}',
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.textSecondary),
                      ),
                      if (device.lastSeenAt != null)
                        Text(
                          'Son görülme: ${device.lastSeenAt}',
                          style: AppTypography.bodySmall
                              .copyWith(color: AppColors.textSecondary),
                        ),
                      if (device.revokedReason != null)
                        Text(
                          'Gerekçe: ${device.revokedReason}',
                          style: AppTypography.bodySmall
                              .copyWith(color: AppColors.textSecondary),
                        ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        children: [
                          if (device.status == TrustedDeviceStatus.pending)
                            OutlinedButton.icon(
                              icon: const Icon(Icons.inbox_outlined, size: 16),
                              label: const Text('Onay Kutusuna Git'),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const ApprovalInboxScreen(),
                                ),
                              ),
                            ),
                          if (device.canBeSuspended)
                            OutlinedButton(
                              onPressed: () => _confirmAndAct(
                                context,
                                ref,
                                title: 'Cihazı Askıya Al',
                                actionLabel: 'Askıya Al',
                                action: (reason) => ref
                                    .read(trustedDeviceGatewayProvider)
                                    .suspendDevice(
                                      organizationId: organizationId,
                                      branchId: branchId,
                                      deviceId: device.deviceId,
                                      reason: reason,
                                    ),
                              ),
                              child: const Text('Askıya Al'),
                            ),
                          if (device.canBeRevoked)
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.error),
                              onPressed: () => _confirmAndAct(
                                context,
                                ref,
                                title: 'Cihazı İptal Et',
                                actionLabel: 'İptal Et',
                                action: (reason) => ref
                                    .read(trustedDeviceGatewayProvider)
                                    .revokeDevice(
                                      organizationId: organizationId,
                                      branchId: branchId,
                                      deviceId: device.deviceId,
                                      reason: reason,
                                    ),
                              ),
                              child: const Text('İptal Et'),
                            ),
                          if (device.canBeRetired)
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.error),
                              onPressed: () => _confirmAndAct(
                                context,
                                ref,
                                title: 'Cihazı Emekliye Ayır',
                                actionLabel: 'Emekliye Ayır',
                                action: (reason) => ref
                                    .read(trustedDeviceGatewayProvider)
                                    .retireDevice(
                                      organizationId: organizationId,
                                      branchId: branchId,
                                      deviceId: device.deviceId,
                                      reason: reason,
                                    ),
                              ),
                              child: const Text('Emekliye Ayır'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final TrustedDeviceStatus status;

  Color _colorFor(TrustedDeviceStatus status) {
    switch (status) {
      case TrustedDeviceStatus.active:
        return AppColors.success;
      case TrustedDeviceStatus.pending:
        return AppColors.warning;
      case TrustedDeviceStatus.suspended:
        return AppColors.warning;
      case TrustedDeviceStatus.revoked:
      case TrustedDeviceStatus.retired:
        return AppColors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(status);
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _statusLabels[status]!,
        style: AppTypography.labelMedium.copyWith(color: color),
      ),
    );
  }
}

final _devicesStreamProvider = StreamProvider.family<List<TrustedDevice>,
    ({String organizationId, String branchId})>((ref, scope) {
  return ref.watch(trustedDeviceRepositoryProvider).watchDevicesForBranch(
        organizationId: scope.organizationId,
        branchId: scope.branchId,
      );
});
