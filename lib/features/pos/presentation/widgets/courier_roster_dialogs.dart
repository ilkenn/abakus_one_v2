import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/courier_type.dart';
import '../../../courier/data/courier_dispatch_gateway.dart';
import '../../../courier/domain/identity/courier.dart';
import '../../data/courier_pool_gateway.dart';
import '../providers/courier_dispatch_dependencies_provider.dart';

/// 2026-11-12 (Faz 3b) — the dispatch board's courier setup, so the pool
/// works without manual database edits: the branch's courier roster with
/// an edit dialog (type, service districts, the linked sign-in e-mail) and
/// the branch's default delivery district. Linking a sign-in, registering
/// an external courier and changing the default district are manager-and-
/// above on the server; the dialogs explain a refusal in Turkish.

String _errorText(String code, String message, {required String denied}) {
  if (code == 'permission-denied' || code == 'permission_denied') {
    return denied;
  }
  if (message.contains('No sign-in account')) {
    return 'Bu e-postayla bir giriş hesabı bulunamadı.';
  }
  if (message.contains('not an active courier')) {
    return 'Bu hesap organizasyonda aktif bir kurye hesabı değil '
        '(Personel ekranından kurye rolü verilmeli).';
  }
  if (message.contains('already linked')) {
    return 'Bu giriş hesabı başka bir kuryeye bağlı.';
  }
  if (message.contains('service district')) {
    return 'Dış kurye için en az bir hizmet ilçesi girin.';
  }
  return 'Kaydedilemedi. Lütfen tekrar deneyin.';
}

class CourierRosterDialog extends ConsumerWidget {
  const CourierRosterDialog({
    super.key,
    required this.organizationId,
    required this.branchId,
  });

  final String organizationId;
  final String branchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final couriersAsync = ref.watch(allCouriersForBranchProvider(branchId));
    return AlertDialog(
      title: const Text('Kuryeler'),
      content: SizedBox(
        width: 480,
        child: couriersAsync.when(
          loading: () => const SizedBox(
              height: 120, child: Center(child: CircularProgressIndicator())),
          error: (_, __) => const Text('Kurye listesi yüklenemedi.'),
          data: (couriers) => couriers.isEmpty
              ? const Text('Bu şubede kayıtlı kurye yok.')
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final courier in couriers)
                        ListTile(
                          key: Key('rosterCourier-${courier.id}'),
                          title: Text(courier.displayName),
                          subtitle: Text([
                            courier.type == CourierType.pool
                                ? 'Dış Kurye · ${courier.serviceDistrictIds.join(', ')}'
                                : 'Dükkan Kuryesi',
                            courier.authEmail == null
                                ? 'Giriş hesabı bağlı değil'
                                : 'Giriş: ${courier.authEmail}',
                          ].join('\n')),
                          isThreeLine: true,
                          trailing: const Icon(Icons.edit_outlined),
                          onTap: () => showDialog<void>(
                            context: context,
                            builder: (_) => CourierEditDialog(
                              organizationId: organizationId,
                              courier: courier,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Kapat'),
        ),
      ],
    );
  }
}

class CourierEditDialog extends ConsumerStatefulWidget {
  const CourierEditDialog({
    super.key,
    required this.organizationId,
    required this.courier,
  });

  final String organizationId;
  final Courier courier;

  @override
  ConsumerState<CourierEditDialog> createState() => _CourierEditDialogState();
}

class _CourierEditDialogState extends ConsumerState<CourierEditDialog> {
  late final _name = TextEditingController(text: widget.courier.displayName);
  late final _phone = TextEditingController(text: widget.courier.phoneNumber);
  late final _districts =
      TextEditingController(text: widget.courier.serviceDistrictIds.join(', '));
  late final _email =
      TextEditingController(text: widget.courier.authEmail ?? '');
  late CourierType _type = widget.courier.type == CourierType.pool
      ? CourierType.pool
      : CourierType.internal;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _districts.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final districts = _districts.text
        .split(',')
        .map((d) => d.trim())
        .where((d) => d.isNotEmpty)
        .toList();
    if (name.isEmpty || phone.isEmpty) {
      setState(() => _error = 'Ad ve telefon zorunludur.');
      return;
    }
    if (_type == CourierType.pool && districts.isEmpty) {
      setState(() => _error = 'Dış kurye için en az bir hizmet ilçesi girin.');
      return;
    }
    final email = _email.text.trim().toLowerCase();
    final emailChanged = email != (widget.courier.authEmail ?? '');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(courierDispatchGatewayProvider).setCourier(
            organizationId: widget.organizationId,
            branchId: widget.courier.primaryBranchId,
            courierId: widget.courier.id,
            displayName: name,
            phoneNumber: phone,
            type: _type,
            serviceDistrictIds:
                _type == CourierType.pool ? districts : const [],
            authEmail: emailChanged ? email : null,
          );
      if (mounted) Navigator.of(context).pop();
    } on CourierDispatchException catch (error) {
      if (!mounted) return;
      setState(() => _error = _errorText(error.code, error.message,
          denied: 'Dış kurye kaydı ve giriş hesabı bağlama yalnızca müdür '
              've üstü tarafından yapılabilir.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Kurye Düzenle — ${widget.courier.displayName}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('editCourierName'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'Ad Soyad'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const Key('editCourierPhone'),
                controller: _phone,
                decoration: const InputDecoration(labelText: 'Telefon'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  ChoiceChip(
                    key: const Key('editCourierInternal'),
                    label: const Text('Dükkan Kuryesi'),
                    selected: _type == CourierType.internal,
                    onSelected: (_) =>
                        setState(() => _type = CourierType.internal),
                  ),
                  ChoiceChip(
                    key: const Key('editCourierPool'),
                    label: const Text('Dış Kurye (Havuz)'),
                    selected: _type == CourierType.pool,
                    onSelected: (_) => setState(() => _type = CourierType.pool),
                  ),
                ],
              ),
              if (_type == CourierType.pool) ...[
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  key: const Key('editCourierDistricts'),
                  controller: _districts,
                  decoration: const InputDecoration(
                    labelText: 'Hizmet İlçeleri (virgülle ayırın)',
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const Key('editCourierEmail'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Giriş Hesabı E-postası',
                  helperText: 'Kuryenin "Kurye Ekranım"a girdiği personel '
                      'hesabı. Boş bırakırsanız bağlantı kaldırılır.',
                  helperMaxLines: 3,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  key: const Key('editCourierError'),
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: AppRadius.kMedium,
                  ),
                  child: Text(_error!,
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.error)),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          key: const Key('saveCourierButton'),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Kaydediliyor...' : 'Kaydet'),
        ),
      ],
    );
  }
}

class BranchPoolSettingsDialog extends ConsumerStatefulWidget {
  const BranchPoolSettingsDialog({
    super.key,
    required this.organizationId,
    required this.branchId,
  });

  final String organizationId;
  final String branchId;

  @override
  ConsumerState<BranchPoolSettingsDialog> createState() =>
      _BranchPoolSettingsDialogState();
}

class _BranchPoolSettingsDialogState
    extends ConsumerState<BranchPoolSettingsDialog> {
  final _district = TextEditingController();
  BranchPoolSettings? _settings;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _district.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = await ref
          .read(courierPoolGatewayProvider)
          .branchSettings(
              organizationId: widget.organizationId, branchId: widget.branchId);
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _district.text = settings.defaultDeliveryDistrictId ?? '';
        _loading = false;
      });
    } on CourierPoolException catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Bölge ayarları yüklenemedi.';
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final settings = await ref
          .read(courierPoolGatewayProvider)
          .setDefaultDistrict(
              organizationId: widget.organizationId,
              branchId: widget.branchId,
              districtId: _district.text.trim());
      if (!mounted) return;
      setState(() => _settings = settings);
      Navigator.of(context).pop();
    } on CourierPoolException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.isPermissionDenied
          ? 'Varsayılan ilçeyi yalnızca müdür ve üstü değiştirebilir.'
          : 'Kaydedilemedi. Lütfen tekrar deneyin.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    return AlertDialog(
      title: const Text('Havuz Bölge Ayarları'),
      content: SizedBox(
        width: 420,
        child: _loading
            ? const SizedBox(
                height: 120, child: Center(child: CircularProgressIndicator()))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Havuza gönderilen paketin ilçesi önce adresten, sonra '
                    'şubenin hizmet bölgelerinden bulunur. İkisi de yoksa '
                    'burada seçtiğiniz varsayılan ilçe kullanılır.',
                    style: AppTypography.bodySmall,
                  ),
                  if (settings != null &&
                      settings.serviceDistrictIds.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        for (final d in settings.serviceDistrictIds)
                          ActionChip(
                            key: Key('serviceDistrict-$d'),
                            label: Text(d),
                            onPressed: () => setState(() => _district.text = d),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    key: const Key('defaultDistrictField'),
                    controller: _district,
                    decoration: const InputDecoration(
                      labelText: 'Varsayılan İlçe',
                      helperText: 'Boş bırakırsanız varsayılan kaldırılır.',
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_error!,
                        key: const Key('poolSettingsError'),
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.error)),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          key: const Key('savePoolSettingsButton'),
          onPressed: _saving || _loading || settings == null ? null : _save,
          child: Text(_saving ? 'Kaydediliyor...' : 'Kaydet'),
        ),
      ],
    );
  }
}
