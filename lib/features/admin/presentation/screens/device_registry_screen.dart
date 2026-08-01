import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../courier/presentation/providers/courier_core_dependencies_provider.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/presentation/providers/kds_dependencies_provider.dart';
import '../../application/use_cases/register_device.dart';
import '../../application/use_cases/set_admin_device_status.dart';
import '../../application/use_cases/set_source_device_active.dart';
import '../../domain/device/admin_device_registration_status.dart';
import '../../domain/device/device_registry_entry.dart';
import '../../domain/device/device_type.dart';
import '../providers/admin_dependencies_provider.dart';

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

/// Unified device registry — Phase 6L (`docs/decisions.md` ADR-023).
/// Lists KDS/courier devices (read/toggle-only projections owned by
/// their own bounded context) alongside admin-registered POS terminal/
/// printer/payment-terminal placeholders (the only device types this
/// screen can actually create). "No real remote restart claim" — no
/// restart/reconnect action exists here, only active/inactive/archive.
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

class _DeviceRegistryScreenState extends ConsumerState<DeviceRegistryScreen> {
  List<DeviceRegistryEntry>? _entries;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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
    final entries = _entries;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Cihaz Kaydı'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Cihaz Kaydet',
            onPressed: _register,
          ),
        ],
      ),
      body: SafeArea(
        child: entries == null
            ? const LoadingView(message: 'Cihazlar yükleniyor...')
            : entries.isEmpty
                ? const EmptyView(
                    icon: Icons.devices_outlined,
                    message: 'Bu şube için kayıtlı cihaz yok.',
                  )
                : ListView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    children: [
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
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
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
                                            onPressed: () =>
                                                _setAdminDeviceStatus(
                                                    entry,
                                                    AdminDeviceRegistrationStatus
                                                        .active),
                                            child: const Text('Aktifleştir'),
                                          ),
                                        if (entry.isActive)
                                          OutlinedButton(
                                            onPressed: () =>
                                                _setAdminDeviceStatus(
                                                    entry,
                                                    AdminDeviceRegistrationStatus
                                                        .inactive),
                                            child: const Text('Pasifleştir '
                                                '(Kaldır)'),
                                          ),
                                        OutlinedButton(
                                          onPressed: () =>
                                              _setAdminDeviceStatus(
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
                  ),
      ),
    );
  }
}
