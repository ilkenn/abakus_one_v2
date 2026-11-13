import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../auth/data/repositories/auth_repository.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

/// ADR-085 (revision) — a staff member changes their own password: current
/// password, new password (at least 8 characters), repeated. Shown only to
/// accounts with a staff role (the caller decides). The change itself goes
/// through `AuthNotifier.changeOwnPassword`; this sheet only collects input
/// and shows the outcome.
class ProfileChangePasswordSheet extends ConsumerStatefulWidget {
  const ProfileChangePasswordSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const ProfileChangePasswordSheet(),
    );
  }

  @override
  ConsumerState<ProfileChangePasswordSheet> createState() =>
      _ProfileChangePasswordSheetState();
}

class _ProfileChangePasswordSheetState
    extends ConsumerState<ProfileChangePasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _repeatController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _repeatController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    PasswordChangeResult result;
    try {
      result = await ref.read(authProvider.notifier).changeOwnPassword(
            currentPassword: _currentController.text,
            newPassword: _newController.text,
          );
    } on AuthServiceUnavailableException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Şifre şu anda değiştirilemiyor. Bağlantınızı kontrol edin.';
      });
      return;
    }
    if (!mounted) return;
    switch (result) {
      case PasswordChangeResult.success:
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          const SnackBar(content: Text('Şifreniz değiştirildi.')),
        );
      case PasswordChangeResult.wrongCurrentPassword:
        setState(() {
          _busy = false;
          _error = 'Mevcut şifreniz hatalı.';
        });
      case PasswordChangeResult.weakPassword:
        setState(() {
          _busy = false;
          _error = 'Yeni şifre en az 8 karakter olmalı.';
        });
    }
  }

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline_rounded),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.xl,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Şifremi Değiştir', style: AppTypography.titleLarge),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              key: const Key('currentPasswordField'),
              controller: _currentController,
              enabled: !_busy,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: _decoration('Mevcut şifre'),
              validator: (value) => (value ?? '').isEmpty
                  ? 'Lütfen mevcut şifrenizi girin'
                  : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              key: const Key('newPasswordField'),
              controller: _newController,
              enabled: !_busy,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: _decoration('Yeni şifre'),
              validator: (value) => (value ?? '').length < 8
                  ? 'Yeni şifre en az 8 karakter olmalı'
                  : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              key: const Key('repeatPasswordField'),
              controller: _repeatController,
              enabled: !_busy,
              obscureText: true,
              decoration: _decoration('Yeni şifre (tekrar)'),
              validator: (value) =>
                  value != _newController.text ? 'Şifreler aynı değil' : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                _error!,
                style: AppTypography.bodySmall.copyWith(color: AppColors.error),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: _busy ? null : _submit,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Şifreyi Değiştir'),
            ),
          ],
        ),
      ),
    );
  }
}
