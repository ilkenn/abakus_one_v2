import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/customer_registration_validation.dart';
import '../../domain/models/customer_gender.dart';
import '../../domain/models/occupation_status.dart';
import '../providers/customer_registration_submit_provider.dart';
import 'birth_date_field.dart';

/// CR.1.2 — Step 1 ("Bilgilerin") of the two-step "Profilini Tamamla"
/// onboarding flow. Field-for-field identical to CR.1/CR.1.1's original
/// single-step form (same widget keys, same validators) — only extracted
/// into its own widget and given an [onSuccess] callback instead of being
/// the screen's entire body. On success, this widget does **not** invoke
/// `finishOnboarding()` itself — the completion-state refresh is
/// deliberately deferred to Step 2 finishing/being skipped (see
/// `CustomerRegistrationSubmitNotifier`'s own doc comment); [onSuccess]
/// only advances the local step, a plain `setState` in the parent
/// orchestrator, never a second completion flag.
class Step1InfoForm extends ConsumerStatefulWidget {
  const Step1InfoForm({super.key, required this.onSuccess});

  final VoidCallback onSuccess;

  @override
  ConsumerState<Step1InfoForm> createState() => _Step1InfoFormState();
}

class _Step1InfoFormState extends ConsumerState<Step1InfoForm> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _workplaceController = TextEditingController();
  final _institutionController = TextEditingController();

  OccupationStatus? _occupationStatus;
  CustomerGender? _gender;
  DateTime? _birthDate;
  bool _showOccupationStatusError = false;
  bool _showGenderError = false;
  String? _birthDateError;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _workplaceController.dispose();
    _institutionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final formValid = _formKey.currentState?.validate() ?? false;
    final occupationValid = _occupationStatus != null;
    final genderValid = _gender != null;
    final birthDateError = validateBirthDate(_birthDate);
    setState(() {
      _showOccupationStatusError = !occupationValid;
      _showGenderError = !genderValid;
      _birthDateError = birthDateError;
    });
    if (!formValid ||
        !occupationValid ||
        !genderValid ||
        birthDateError != null) {
      return;
    }

    final notifier = ref.read(customerRegistrationSubmitProvider.notifier);
    final success = await notifier.submit(
      firstName: _firstNameController.text,
      lastName: _lastNameController.text,
      email: _emailController.text,
      occupationStatus: _occupationStatus!,
      workplaceName: _occupationStatus == OccupationStatus.working
          ? _workplaceController.text
          : null,
      educationalInstitutionName: _occupationStatus == OccupationStatus.student
          ? _institutionController.text
          : null,
      gender: _gender!,
      birthDate: _birthDate!,
    );
    // No navigation call here — Step 1 success only advances the LOCAL
    // step (widget.onSuccess); the router-driven transition off this
    // whole screen happens only once Step 2 finishes/is skipped. On
    // failure, submitState.errorMessage renders below.
    if (success) widget.onSuccess();
  }

  InputDecoration _fieldDecoration({
    required String label,
    IconData? icon,
    bool readOnly = false,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: icon != null ? Icon(icon) : null,
      filled: readOnly,
      fillColor: readOnly ? AppColors.surfaceVariant : null,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.lg,
      ),
      border: const OutlineInputBorder(
        borderRadius: AppRadius.kExtraLarge,
        borderSide: BorderSide(color: AppColors.border),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: AppRadius.kExtraLarge,
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: AppRadius.kExtraLarge,
        borderSide: BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final phoneNumber =
        ref.watch(authProvider.select((state) => state.session?.phoneNumber)) ??
            '';
    final submitState = ref.watch(customerRegistrationSubmitProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.xl),
              borderRadius: AppRadius.kExtraLarge,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    key: const Key('completeProfileFirstNameField'),
                    controller: _firstNameController,
                    textCapitalization: TextCapitalization.words,
                    style: AppTypography.bodyLarge,
                    decoration: _fieldDecoration(
                      label: 'Ad',
                      icon: Icons.person_outline_rounded,
                    ),
                    validator: (value) =>
                        validateRequiredName(value, fieldLabel: 'Ad'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextFormField(
                    key: const Key('completeProfileLastNameField'),
                    controller: _lastNameController,
                    textCapitalization: TextCapitalization.words,
                    style: AppTypography.bodyLarge,
                    decoration: _fieldDecoration(
                      label: 'Soyad',
                      icon: Icons.person_outline_rounded,
                    ),
                    validator: (value) =>
                        validateRequiredName(value, fieldLabel: 'Soyad'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextFormField(
                    key: const Key('completeProfileEmailField'),
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    style: AppTypography.bodyLarge,
                    decoration: _fieldDecoration(
                      label: 'E-posta',
                      icon: Icons.mail_outline_rounded,
                    ),
                    validator: validateEmail,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  BirthDateField(
                    value: _birthDate,
                    errorText: _birthDateError,
                    onChanged: (date) => setState(() {
                      _birthDate = date;
                      _birthDateError = null;
                    }),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextFormField(
                    key: const Key('completeProfilePhoneField'),
                    initialValue: phoneNumber,
                    readOnly: true,
                    enabled: false,
                    style: AppTypography.bodyLarge.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    decoration: _fieldDecoration(
                      label: 'Telefon',
                      icon: Icons.phone_iphone_rounded,
                      readOnly: true,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.xl),
              borderRadius: AppRadius.kExtraLarge,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Çalışma / eğitim durumu',
                    style: AppTypography.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final status in OccupationStatus.values)
                        ChoiceChip(
                          key: Key('occupationStatusChip_${status.name}'),
                          label: Text(occupationStatusLabel(status)),
                          selected: _occupationStatus == status,
                          onSelected: (_) => setState(() {
                            _occupationStatus = status;
                            _showOccupationStatusError = false;
                          }),
                          selectedColor: AppColors.primaryExtraLight,
                          labelStyle: AppTypography.bodyMedium.copyWith(
                            color: _occupationStatus == status
                                ? AppColors.primary
                                : AppColors.textPrimary,
                            fontWeight: _occupationStatus == status
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.kPill,
                            side: BorderSide(
                              color: _occupationStatus == status
                                  ? AppColors.primary
                                  : AppColors.border,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (_showOccupationStatusError) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Lütfen bir seçim yap.',
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.error),
                    ),
                  ],
                  if (_occupationStatus == OccupationStatus.working) ...[
                    const SizedBox(height: AppSpacing.lg),
                    TextFormField(
                      key: const Key('completeProfileWorkplaceField'),
                      controller: _workplaceController,
                      style: AppTypography.bodyLarge,
                      decoration: _fieldDecoration(
                        label: 'Şirket / İş Yeri',
                        icon: Icons.work_outline_rounded,
                      ),
                      validator: (value) => validateInstitutionField(
                        value,
                        fieldLabel: 'Şirket / İş Yeri',
                      ),
                    ),
                  ] else if (_occupationStatus == OccupationStatus.student) ...[
                    const SizedBox(height: AppSpacing.lg),
                    TextFormField(
                      key: const Key('completeProfileInstitutionField'),
                      controller: _institutionController,
                      style: AppTypography.bodyLarge,
                      decoration: _fieldDecoration(
                        label: 'Okul / Eğitim Kurumu',
                        icon: Icons.school_outlined,
                      ),
                      validator: (value) => validateInstitutionField(
                        value,
                        fieldLabel: 'Okul / Eğitim Kurumu',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.xl),
              borderRadius: AppRadius.kExtraLarge,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Cinsiyet', style: AppTypography.titleMedium),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final gender in CustomerGender.values)
                        ChoiceChip(
                          key: Key('genderChip_${gender.name}'),
                          label: Text(customerGenderLabel(gender)),
                          selected: _gender == gender,
                          onSelected: (_) => setState(() {
                            _gender = gender;
                            _showGenderError = false;
                          }),
                          selectedColor: AppColors.primaryExtraLight,
                          labelStyle: AppTypography.bodyMedium.copyWith(
                            color: _gender == gender
                                ? AppColors.primary
                                : AppColors.textPrimary,
                            fontWeight: _gender == gender
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.kPill,
                            side: BorderSide(
                              color: _gender == gender
                                  ? AppColors.primary
                                  : AppColors.border,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (_showGenderError) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Lütfen bir seçim yap.',
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.error),
                    ),
                  ],
                ],
              ),
            ),
            if (submitState.errorMessage != null) ...[
              const SizedBox(height: AppSpacing.xl),
              Container(
                key: const Key('completeProfileErrorBanner'),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: AppRadius.kMedium,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: AppColors.error, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        submitState.errorMessage!,
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.error),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xxl),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                key: const Key('completeProfileSubmitButton'),
                onPressed: submitState.isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.lg,
                  ),
                  shape: const RoundedRectangleBorder(
                    borderRadius: AppRadius.kExtraLarge,
                  ),
                ),
                child: submitState.isSubmitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.onPrimary,
                        ),
                      )
                    : Text(
                        'Devam Et',
                        style: AppTypography.bodyLarge.copyWith(
                          color: AppColors.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
