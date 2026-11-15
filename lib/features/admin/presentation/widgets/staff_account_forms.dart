import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../auth/domain/phone_number.dart';
import '../../../courier/domain/pay/courier_pay_models.dart';
import '../../../pos/domain/authorization/staff_role.dart';
import 'courier_pay_fields.dart';

/// ADR-085 (revision) — Turkish names of the staff roles, for the panel.
String staffRoleLabel(StaffRole role) => switch (role) {
      StaffRole.courier => 'Kurye',
      StaffRole.staff => 'Personel',
      StaffRole.cashier => 'Kasiyer',
      StaffRole.packingLead => 'Mutfak Paket Yetkilisi',
      StaffRole.manager => 'Müdür',
      StaffRole.admin => 'Yönetici',
      StaffRole.tenantOwner => 'Sahip',
    };

/// The roles the signed-in actor can hand out from the panel — a
/// convenience for the form only; the server enforces the real rule
/// (`functions/src/staffAccounts.ts`). A manager offers the roles below
/// the manager tier; an admin or owner also offers manager and admin.
List<StaffRole> assignableStaffRoles(Set<StaffRole> actorRoles) {
  const lower = [
    StaffRole.cashier,
    StaffRole.courier,
    StaffRole.staff,
    StaffRole.packingLead,
  ];
  final isAdminTier = actorRoles.contains(StaffRole.admin) ||
      actorRoles.contains(StaffRole.tenantOwner);
  return isAdminTier
      ? const [...lower, StaffRole.manager, StaffRole.admin]
      : lower;
}

/// What "Personel Ekle" collects. The phone number is already E.164.
class NewStaffAccountInput {
  const NewStaffAccountInput({
    required this.firstName,
    required this.lastName,
    required this.phoneNumber,
    required this.password,
    required this.roles,
    required this.branchId,
    this.courierPay,
  });

  final String firstName;
  final String lastName;
  final String phoneNumber;
  final String password;
  final Set<StaffRole> roles;
  final String branchId;

  /// ADR-085 stage 5 — the courier's first rate (courier role only).
  final CourierPayRateInput? courierPay;
}

String? _passwordError(String? value) =>
    (value ?? '').length < 8 ? 'Şifre en az 8 karakter olmalı' : null;

/// "Personel Ekle": first and last name, phone number, password, roles and
/// branch. Returns the input, or `null` when cancelled.
class StaffAccountCreateSheet extends StatefulWidget {
  const StaffAccountCreateSheet({
    super.key,
    required this.assignableRoles,
    required this.branchIds,
    required this.initialBranchId,
    this.allowPoolCourier = false,
  });

  final List<StaffRole> assignableRoles;
  final List<String> branchIds;
  final String initialBranchId;

  /// Admin/owner: may add a pool courier (ADR-085 stage 5).
  final bool allowPoolCourier;

  static Future<NewStaffAccountInput?> show(
    BuildContext context, {
    required List<StaffRole> assignableRoles,
    required List<String> branchIds,
    required String initialBranchId,
    bool allowPoolCourier = false,
  }) {
    return showModalBottomSheet<NewStaffAccountInput>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => StaffAccountCreateSheet(
        assignableRoles: assignableRoles,
        branchIds: branchIds,
        initialBranchId: initialBranchId,
        allowPoolCourier: allowPoolCourier,
      ),
    );
  }

  @override
  State<StaffAccountCreateSheet> createState() =>
      _StaffAccountCreateSheetState();
}

class _StaffAccountCreateSheetState extends State<StaffAccountCreateSheet> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final Set<StaffRole> _roles = {};
  late String _branchId = widget.initialBranchId;
  late final CourierPayDraft _pay =
      CourierPayDraft(allowPool: widget.allowPoolCourier);
  bool _rolesError = false;

  bool get _isCourier => _roles.contains(StaffRole.courier);

  @override
  void dispose() {
    _pay.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  void _save() {
    final formOk = _formKey.currentState?.validate() ?? false;
    setState(() => _rolesError = _roles.isEmpty);
    if (!formOk || _roles.isEmpty) return;
    Navigator.of(context).pop(NewStaffAccountInput(
      firstName: _firstName.text.trim(),
      lastName: _lastName.text.trim(),
      phoneNumber: TurkishPhoneNumber.normalize(_phone.text)!,
      password: _password.text,
      roles: Set.of(_roles),
      branchId: _branchId,
      courierPay: _isCourier ? _pay.toInput() : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.xl,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Personel Ekle', style: AppTypography.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Hesap kaydettiğiniz anda aktif olur. Personel telefon '
                'numarası ve bu şifre ile giriş yapar.',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const Key('staffFirstNameField'),
                      controller: _firstName,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Ad'),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'Ad gerekli' : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextFormField(
                      key: const Key('staffLastNameField'),
                      controller: _lastName,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Soyad'),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'Soyad gerekli' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                key: const Key('staffPhoneField'),
                controller: _phone,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: const InputDecoration(
                  labelText: 'Telefon Numarası',
                  prefixText: '+90 ',
                  hintText: '5XX XXX XX XX',
                ),
                validator: (v) => TurkishPhoneNumber.isValidLocalNumber(v ?? '')
                    ? null
                    : 'Geçerli bir telefon numarası girin',
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                key: const Key('staffPasswordField'),
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Şifre (en az 8 karakter)',
                ),
                validator: _passwordError,
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text('Rol', style: AppTypography.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final role in widget.assignableRoles)
                    FilterChip(
                      key: Key('staffRoleChip-${role.name}'),
                      label: Text(staffRoleLabel(role)),
                      selected: _roles.contains(role),
                      onSelected: (selected) => setState(() {
                        selected ? _roles.add(role) : _roles.remove(role);
                        _rolesError = false;
                      }),
                    ),
                ],
              ),
              if (_rolesError) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'En az bir rol seçin',
                  style:
                      AppTypography.bodySmall.copyWith(color: AppColors.error),
                ),
              ],
              if (_isCourier) ...[
                const SizedBox(height: AppSpacing.lg),
                CourierPayFields(draft: _pay),
              ],
              if (widget.branchIds.length > 1) ...[
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<String>(
                  initialValue: _branchId,
                  decoration: const InputDecoration(labelText: 'Şube'),
                  items: [
                    for (final id in widget.branchIds)
                      DropdownMenuItem(value: id, child: Text(id)),
                  ],
                  onChanged: (value) =>
                      setState(() => _branchId = value ?? _branchId),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              ElevatedButton(
                key: const Key('staffCreateSaveButton'),
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: const Text('Kaydet'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sets a staff member's new password (typed twice). Returns it, or `null`.
Future<String?> showStaffPasswordDialog(
  BuildContext context, {
  required String memberName,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _StaffPasswordDialog(memberName: memberName),
  );
}

class _StaffPasswordDialog extends StatefulWidget {
  const _StaffPasswordDialog({required this.memberName});

  final String memberName;

  @override
  State<_StaffPasswordDialog> createState() => _StaffPasswordDialogState();
}

class _StaffPasswordDialogState extends State<_StaffPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _repeat = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.memberName} — Şifre Değiştir'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('staffNewPasswordField'),
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Yeni şifre'),
              validator: _passwordError,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              key: const Key('staffRepeatPasswordField'),
              controller: _repeat,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'Yeni şifre (tekrar)'),
              validator: (v) =>
                  v != _password.text ? 'Şifreler aynı değil' : null,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Kişinin açık oturumları kapanır; yeni şifreyle tekrar giriş '
              'yapması gerekir.',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          key: const Key('staffPasswordSaveButton'),
          onPressed: () {
            if (_formKey.currentState?.validate() ?? false) {
              Navigator.of(context).pop(_password.text);
            }
          },
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}

/// What the staff edit form returns: the roles, and a new courier rate
/// when one was typed (courier role only, and only if it changed).
class StaffEditResult {
  const StaffEditResult({
    required this.roles,
    this.courierPay,
    this.issuesInvoice,
  });

  final Set<StaffRole> roles;
  final CourierPayRateInput? courierPay;

  /// Stage 6A — the new "Fatura Keser" value, only when it changed.
  final bool? issuesInvoice;
}

/// Changes a staff member's roles and — for a courier — its pay (ADR-085
/// stage 5: a new rate version from today or a later day). Returns `null`
/// when cancelled.
Future<StaffEditResult?> showStaffRolesDialog(
  BuildContext context, {
  required String memberName,
  required Set<StaffRole> current,
  required List<StaffRole> assignableRoles,
  CourierPayRate? currentCourierRate,
  bool currentIssuesInvoice = false,
  bool allowPoolCourier = false,
}) {
  return showDialog<StaffEditResult>(
    context: context,
    builder: (_) => _StaffEditDialog(
      memberName: memberName,
      current: current,
      assignableRoles: assignableRoles,
      currentCourierRate: currentCourierRate,
      currentIssuesInvoice: currentIssuesInvoice,
      allowPoolCourier: allowPoolCourier,
    ),
  );
}

class _StaffEditDialog extends StatefulWidget {
  const _StaffEditDialog({
    required this.memberName,
    required this.current,
    required this.assignableRoles,
    required this.currentCourierRate,
    required this.currentIssuesInvoice,
    required this.allowPoolCourier,
  });

  final String memberName;
  final Set<StaffRole> current;
  final List<StaffRole> assignableRoles;
  final CourierPayRate? currentCourierRate;
  final bool currentIssuesInvoice;
  final bool allowPoolCourier;

  @override
  State<_StaffEditDialog> createState() => _StaffEditDialogState();
}

class _StaffEditDialogState extends State<_StaffEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final Set<StaffRole> _selected = {
    ...widget.current.where(widget.assignableRoles.contains),
  };
  late final CourierPayDraft _pay = CourierPayDraft(
    initial: widget.currentCourierRate,
    allowPool: widget.allowPoolCourier,
    withEffectiveDate: true,
    initialIssuesInvoice: widget.currentIssuesInvoice,
  );

  @override
  void dispose() {
    _pay.dispose();
    super.dispose();
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final isCourier = _selected.contains(StaffRole.courier);
    final input = isCourier ? _pay.toInput() : null;
    Navigator.of(context).pop(StaffEditResult(
      roles: Set.of(_selected),
      courierPay: input != null && input.differsFrom(widget.currentCourierRate)
          ? input
          : null,
      issuesInvoice:
          isCourier && _pay.issuesInvoice != widget.currentIssuesInvoice
              ? _pay.issuesInvoice
              : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isCourier = _selected.contains(StaffRole.courier);
    return AlertDialog(
      title: Text('${widget.memberName} — '
          '${isCourier ? 'Rol ve Ücret' : 'Rolleri Değiştir'}'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final role in widget.assignableRoles)
                    FilterChip(
                      key: Key('staffEditRoleChip-${role.name}'),
                      label: Text(staffRoleLabel(role)),
                      selected: _selected.contains(role),
                      onSelected: (value) => setState(() {
                        value ? _selected.add(role) : _selected.remove(role);
                      }),
                    ),
                ],
              ),
              if (isCourier) ...[
                const SizedBox(height: AppSpacing.lg),
                CourierPayFields(draft: _pay),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          key: const Key('staffRolesSaveButton'),
          onPressed: _selected.isEmpty ? null : _save,
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
