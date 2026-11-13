import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../auth/domain/phone_number.dart';
import '../../../pos/domain/authorization/staff_role.dart';

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
  });

  final String firstName;
  final String lastName;
  final String phoneNumber;
  final String password;
  final Set<StaffRole> roles;
  final String branchId;
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
  });

  final List<StaffRole> assignableRoles;
  final List<String> branchIds;
  final String initialBranchId;

  static Future<NewStaffAccountInput?> show(
    BuildContext context, {
    required List<StaffRole> assignableRoles,
    required List<String> branchIds,
    required String initialBranchId,
  }) {
    return showModalBottomSheet<NewStaffAccountInput>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => StaffAccountCreateSheet(
        assignableRoles: assignableRoles,
        branchIds: branchIds,
        initialBranchId: initialBranchId,
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
  bool _rolesError = false;

  @override
  void dispose() {
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

/// Changes a staff member's roles. Returns the new set, or `null`.
Future<Set<StaffRole>?> showStaffRolesDialog(
  BuildContext context, {
  required String memberName,
  required Set<StaffRole> current,
  required List<StaffRole> assignableRoles,
}) {
  final selected = <StaffRole>{...current.where(assignableRoles.contains)};
  return showDialog<Set<StaffRole>>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('$memberName — Rolleri Değiştir'),
        content: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final role in assignableRoles)
              FilterChip(
                key: Key('staffEditRoleChip-${role.name}'),
                label: Text(staffRoleLabel(role)),
                selected: selected.contains(role),
                onSelected: (value) => setState(() {
                  value ? selected.add(role) : selected.remove(role);
                }),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            key: const Key('staffRolesSaveButton'),
            onPressed: selected.isEmpty
                ? null
                : () => Navigator.of(dialogContext).pop(Set.of(selected)),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    ),
  );
}
