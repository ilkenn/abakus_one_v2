import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/phone_number.dart';
import '../providers/auth_provider.dart';

/// MVP customer authentication is phone number + OTP only — no email, no
/// password. See `docs/master_spec_migration.md` for the Authentication
/// phase's design decisions.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final sent = await ref.read(authProvider.notifier).requestOtp(
          _phoneController.text,
        );
    if (!mounted || !sent) return;

    context.push(AppRoutes.otp);
  }

  void _continueAsGuest() {
    ref.read(authProvider.notifier).loginAsGuest();
    context.go(AppRoutes.main);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.blur_on_rounded,
                    size: 64,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Text(
                    'Abaküs\'e Hoş Geldiniz',
                    style: AppTypography.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Giriş yapmak için telefon numaranı gir, sana bir kod gönderelim.',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Telefon Numarası',
                      prefixText: '+90 ',
                      prefixIcon: Icon(Icons.phone_iphone_rounded),
                      hintText: '5XX XXX XX XX',
                    ),
                    validator: (value) {
                      final digits = value ?? '';
                      if (digits.isEmpty) {
                        return 'Lütfen telefon numaranızı giriniz';
                      }
                      if (!TurkishPhoneNumber.isValidLocalNumber(digits)) {
                        return 'Lütfen geçerli bir telefon numarası giriniz';
                      }
                      return null;
                    },
                  ),
                  if (authState.error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      authState.error!,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  ElevatedButton(
                    onPressed: authState.isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                    ),
                    child: authState.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('OTP Gönder'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton(
                    onPressed: authState.isLoading ? null : _continueAsGuest,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                    ),
                    child: const Text('Misafir Olarak Devam Et'),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Devam ederek Kullanım Koşulları ve Gizlilik Politikası\'nı kabul etmiş olursun.',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
