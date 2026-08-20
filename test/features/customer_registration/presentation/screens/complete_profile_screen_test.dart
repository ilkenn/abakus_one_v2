import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/customer_photos/data/customer_photo_gateway.dart';
import 'package:abakus_one_v2/features/customer_photos/data/customer_photo_picker.dart';
import 'package:abakus_one_v2/features/customer_photos/data/customer_photo_storage_client.dart';
import 'package:abakus_one_v2/features/customer_photos/presentation/providers/customer_photo_providers.dart';
import 'package:abakus_one_v2/features/customer_registration/data/customer_registration_gateway.dart';
import 'package:abakus_one_v2/features/customer_registration/domain/models/customer_gender.dart';
import 'package:abakus_one_v2/features/customer_registration/domain/models/occupation_status.dart';
import 'package:abakus_one_v2/features/customer_registration/presentation/providers/customer_registration_providers.dart';
import 'package:abakus_one_v2/features/customer_registration/presentation/screens/complete_profile_screen.dart';
import 'package:abakus_one_v2/shared/models/customer_photo.dart';
import 'package:abakus_one_v2/shared/widgets/calendar/signature_calendar.dart';

/// CR.1.2 — "Profilini Tamamla" is now a two-step onboarding flow: Step 1
/// (the mandatory CR.1/CR.1.1 form, unchanged field-for-field) and Step 2
/// (the optional profile photo). `pumpScreen` overrides the customer
/// registration gateway (as before) plus the customer-photos providers
/// `Step2PhotoStep` depends on — a minimal, mostly-unused-by-default set,
/// since these tests exercise Step 2 only via "Şimdilik Geç"; the deep
/// photo-upload matrix (pick/upload/retry/quota) lives in its own
/// `step2_photo_step_test.dart`.
void main() {
  AuthState realCustomerState() {
    return AuthState(
      isAuthenticated: true,
      isGuest: false,
      session: AuthSession(
        uid: 'customer-uid-1',
        phoneNumber: '+905551234567',
        createdAt: DateTime(2026, 1, 1),
        expiresAt: DateTime(2027, 1, 1),
      ),
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    _FakeCustomerRegistrationGateway? gateway,
  }) async {
    // A two-step form with a fixed header (title + step indicator) above
    // the scrollable step content needs more room than the default
    // 800x600 test surface to keep WidgetTester's hit-testing reliable
    // for elements near the bottom of Step 1's own long form.
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider
              .overrideWith(() => SeededAuthNotifier(realCustomerState())),
          customerRegistrationGatewayProvider
              .overrideWithValue(gateway ?? _FakeCustomerRegistrationGateway()),
          customerPhotoGatewayProvider
              .overrideWithValue(const _FakeCustomerPhotoGateway()),
          customerPhotoStorageClientProvider
              .overrideWithValue(const _FakeCustomerPhotoStorageClient()),
          customerPhotoPickerProvider
              .overrideWithValue(const _FakeCustomerPhotoPicker()),
        ],
        child: const MaterialApp(home: CompleteProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  // The form is a long SingleChildScrollView, taller than the visible
  // viewport — every tap target below the fold needs to be scrolled into
  // view first, or WidgetTester's hit test silently misses it (a real,
  // previously-hit gotcha, not a hypothetical one).
  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
  }

  Future<void> fillRequiredTextFields(WidgetTester tester) async {
    await tester.enterText(
        find.byKey(const Key('completeProfileFirstNameField')), 'Ayşe');
    await tester.enterText(
        find.byKey(const Key('completeProfileLastNameField')), 'Yılmaz');
    await tester.enterText(
        find.byKey(const Key('completeProfileEmailField')), 'ayse@example.com');
  }

  // CR.1.1 — opens the BirthDateField's bottom sheet, picks a year close
  // to today (so it's already built within GridView.builder's initial
  // viewport, no scrolling needed) and a day in the default-visible
  // January of that year (no month navigation needed either).
  Future<void> selectBirthDate(
    WidgetTester tester, {
    int year = 2020,
    String day = '15',
  }) async {
    await tapKey(tester, 'completeProfileBirthDateField');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('birthDateYearOption_$year')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(SignatureCalendar),
        matching: find.text(day),
      ),
    );
    await tester.pumpAndSettle();
  }

  // CR.1.2 — fills every Step 1 field and taps "Devam Et", landing on
  // Step 2 ("Profil Fotoğrafın").
  Future<void> advanceToStep2(WidgetTester tester) async {
    await fillRequiredTextFields(tester);
    await tapKey(tester, 'occupationStatusChip_other');
    await tester.pump();
    await tapKey(tester, 'genderChip_female');
    await tester.pump();
    await selectBirthDate(tester);
    await tapKey(tester, 'completeProfileSubmitButton');
    await tester.pumpAndSettle();
  }

  testWidgets(
      'shows the read-only phone number sourced from the verified auth session',
      (tester) async {
    await pumpScreen(tester);

    final phoneField = tester.widget<TextFormField>(
      find.byKey(const Key('completeProfilePhoneField')),
    );
    expect(phoneField.enabled, isFalse);
    expect(find.text('+905551234567'), findsOneWidget);
  });

  testWidgets(
      'required field validation blocks submission with empty Ad/Soyad/E-posta',
      (tester) async {
    final gateway = _FakeCustomerRegistrationGateway();
    await pumpScreen(tester, gateway: gateway);

    await tapKey(tester, 'completeProfileSubmitButton');
    await tester.pumpAndSettle();

    expect(gateway.submitCalls, isEmpty);
    expect(find.text('Ad gerekli.'), findsOneWidget);
  });

  testWidgets(
      'the occupationStatus selector requires an explicit choice — no silent default',
      (tester) async {
    final gateway = _FakeCustomerRegistrationGateway();
    await pumpScreen(tester, gateway: gateway);

    await fillRequiredTextFields(tester);
    await tapKey(tester, 'genderChip_preferNotToSay');
    await tester.pump();

    await tapKey(tester, 'completeProfileSubmitButton');
    await tester.pumpAndSettle();

    expect(gateway.submitCalls, isEmpty);
    expect(find.text('Lütfen bir seçim yap.'), findsOneWidget);
  });

  testWidgets(
      'selecting "Çalışıyorum" reveals the Şirket / İş Yeri field, which is required',
      (tester) async {
    await pumpScreen(tester);

    expect(
        find.byKey(const Key('completeProfileWorkplaceField')), findsNothing);

    await tapKey(tester, 'occupationStatusChip_working');
    await tester.pump();

    expect(
        find.byKey(const Key('completeProfileWorkplaceField')), findsOneWidget);
    expect(
        find.byKey(const Key('completeProfileInstitutionField')), findsNothing);
  });

  testWidgets(
      'selecting "Öğrenciyim" reveals "Okul / Eğitim Kurumu" — never labeled university-only',
      (tester) async {
    await pumpScreen(tester);

    await tapKey(tester, 'occupationStatusChip_student');
    await tester.pump();

    expect(find.byKey(const Key('completeProfileInstitutionField')),
        findsOneWidget);
    expect(find.text('Okul / Eğitim Kurumu'), findsOneWidget);
    expect(find.textContaining('Üniversite'), findsNothing);
  });

  testWidgets('selecting "Diğer" shows neither conditional field',
      (tester) async {
    await pumpScreen(tester);

    await tapKey(tester, 'occupationStatusChip_working');
    await tester.pump();
    expect(
        find.byKey(const Key('completeProfileWorkplaceField')), findsOneWidget);

    await tapKey(tester, 'occupationStatusChip_other');
    await tester.pump();

    expect(
        find.byKey(const Key('completeProfileWorkplaceField')), findsNothing);
    expect(
        find.byKey(const Key('completeProfileInstitutionField')), findsNothing);
  });

  testWidgets(
      'the gender selector shows all three choices including Belirtmek istemiyorum as a first-class option',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('Kadın'), findsOneWidget);
    expect(find.text('Erkek'), findsOneWidget);
    expect(find.text('Belirtmek istemiyorum'), findsOneWidget);
  });

  testWidgets(
      'a fully valid Step 1 submission calls the gateway exactly once with the entered values',
      (tester) async {
    final gateway = _FakeCustomerRegistrationGateway();
    await pumpScreen(tester, gateway: gateway);

    await fillRequiredTextFields(tester);
    await tapKey(tester, 'occupationStatusChip_other');
    await tester.pump();
    await tapKey(tester, 'genderChip_female');
    await tester.pump();
    await selectBirthDate(tester);

    await tapKey(tester, 'completeProfileSubmitButton');
    await tester.pumpAndSettle();

    expect(gateway.submitCalls, hasLength(1));
    expect(gateway.submitCalls.single['firstName'], 'Ayşe');
    expect(
        gateway.submitCalls.single['occupationStatus'], OccupationStatus.other);
    expect(gateway.submitCalls.single['gender'], CustomerGender.female);
    expect(gateway.submitCalls.single['birthDate'], '2020-01-15');
  });

  testWidgets(
      'submit is blocked and shows "Doğum tarihi gerekli." when no birth date has been selected',
      (tester) async {
    final gateway = _FakeCustomerRegistrationGateway();
    await pumpScreen(tester, gateway: gateway);

    await fillRequiredTextFields(tester);
    await tapKey(tester, 'occupationStatusChip_other');
    await tester.pump();
    await tapKey(tester, 'genderChip_female');
    await tester.pump();

    await tapKey(tester, 'completeProfileSubmitButton');
    await tester.pumpAndSettle();

    expect(gateway.submitCalls, isEmpty);
    expect(find.text('Doğum tarihi gerekli.'), findsOneWidget);
  });

  testWidgets(
      'a selected birth date remains clearly visible on the field before submission',
      (tester) async {
    await pumpScreen(tester);

    await selectBirthDate(tester);

    expect(find.byKey(const Key('completeProfileBirthDateDisplay')),
        findsOneWidget);
    expect(find.text('15.01.2020'), findsOneWidget);
  });

  testWidgets(
      'double-tapping the Step 1 submit button never sends two callable requests',
      (tester) async {
    final gateway = _FakeCustomerRegistrationGateway(
      submitDelay: const Duration(milliseconds: 50),
    );
    await pumpScreen(tester, gateway: gateway);

    await fillRequiredTextFields(tester);
    await tapKey(tester, 'occupationStatusChip_other');
    await tester.pump();
    await tapKey(tester, 'genderChip_female');
    await tester.pump();
    await selectBirthDate(tester);

    final submitFinder = find.byKey(const Key('completeProfileSubmitButton'));
    await tester.ensureVisible(submitFinder);
    await tester.pumpAndSettle();
    await tester.tap(submitFinder);
    await tester.pump();
    await tester.tap(submitFinder);
    await tester.pumpAndSettle();

    expect(gateway.submitCalls, hasLength(1));
  });

  testWidgets(
      'a Step 1 gateway failure shows an error banner instead of silently doing nothing',
      (tester) async {
    final gateway = _FakeCustomerRegistrationGateway(
      submitError:
          const CustomerRegistrationGatewayException('unknown', 'boom'),
    );
    await pumpScreen(tester, gateway: gateway);

    await fillRequiredTextFields(tester);
    await tapKey(tester, 'occupationStatusChip_other');
    await tester.pump();
    await tapKey(tester, 'genderChip_female');
    await tester.pump();
    await selectBirthDate(tester);

    await tapKey(tester, 'completeProfileSubmitButton');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('completeProfileErrorBanner')), findsOneWidget);
    // Step 1 failure never advances to Step 2.
    expect(find.byKey(const Key('step2PhotoSkipButton')), findsNothing);
  });

  testWidgets('back navigation cannot bypass the mandatory completion screen',
      (tester) async {
    await pumpScreen(tester);

    final popScope = tester.widget<PopScope>(find.byType(PopScope));
    expect(popScope.canPop, isFalse);
  });

  testWidgets(
      'a resolver-level backend failure shows the retry error view, not the form — never silently treated as complete or incomplete',
      (tester) async {
    final gateway = _FakeCustomerRegistrationGateway(
      completionStateError: const CustomerRegistrationGatewayException(
        'permission-denied',
        'boom',
      ),
    );
    await pumpScreen(tester, gateway: gateway);

    expect(
        find.byKey(const Key('completeProfileFirstNameField')), findsNothing);
    expect(find.text('Tekrar Dene'), findsOneWidget);
  });

  // =========================================================================
  // CR.1.2 — two-step onboarding
  // =========================================================================

  testWidgets(
      'a successful Step 1 submission advances locally to Step 2 ("Profil Fotoğrafın") — Step 1 fields are gone from the tree',
      (tester) async {
    await pumpScreen(tester);

    await advanceToStep2(tester);

    expect(find.byKey(const Key('step2PhotoTitle')), findsOneWidget);
    expect(find.byKey(const Key('step2PhotoSkipButton')), findsOneWidget);
    expect(
        find.byKey(const Key('completeProfileFirstNameField')), findsNothing);
  });

  testWidgets(
      'completing Step 1 does NOT invalidate the completion-state provider — the router never yanks the customer to /main mid-Step-2',
      (tester) async {
    final gateway = _FakeCustomerRegistrationGateway();
    await pumpScreen(tester, gateway: gateway);
    expect(gateway.completionStateCalls, 1, reason: 'the initial screen mount');

    await advanceToStep2(tester);

    expect(gateway.completionStateCalls, 1,
        reason: 'Step 1 success alone must never trigger a re-fetch');
  });

  testWidgets(
      'photo is optional — "Şimdilik Geç" on Step 2 finishes onboarding and invalidates the completion-state provider',
      (tester) async {
    final gateway = _FakeCustomerRegistrationGateway();
    await pumpScreen(tester, gateway: gateway);
    await advanceToStep2(tester);
    expect(gateway.completionStateCalls, 1);

    await tapKey(tester, 'step2PhotoSkipButton');
    await tester.pumpAndSettle();

    expect(gateway.completionStateCalls, 2,
        reason: '"Şimdilik Geç" is the ONE re-fetch trigger for this flow');
  });

  testWidgets(
      'Step 2 shows the required title and body copy, and no photo has been forced',
      (tester) async {
    await pumpScreen(tester);
    await advanceToStep2(tester);

    expect(find.byKey(const Key('step2PhotoTitle')), findsOneWidget);
    expect(
      find.textContaining('Fotoğrafın yayınlanmadan önce onaylanır'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('step2PhotoAddButton')), findsOneWidget);
    expect(find.byKey(const Key('step2PhotoSkipButton')), findsOneWidget);
  });
}

class _FakeCustomerRegistrationGateway implements CustomerRegistrationGateway {
  _FakeCustomerRegistrationGateway({
    this.submitError,
    this.submitDelay,
    this.completionStateError,
  });

  final CustomerRegistrationGatewayException? submitError;
  final Duration? submitDelay;
  final CustomerRegistrationGatewayException? completionStateError;
  final List<Map<String, dynamic>> submitCalls = [];
  int completionStateCalls = 0;

  @override
  Future<CompleteCustomerProfileResult> completeCustomerProfile({
    required String firstName,
    required String lastName,
    required String email,
    required OccupationStatus occupationStatus,
    String? workplaceName,
    String? educationalInstitutionName,
    required CustomerGender gender,
    required String birthDate,
  }) async {
    submitCalls.add({
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'occupationStatus': occupationStatus,
      'workplaceName': workplaceName,
      'educationalInstitutionName': educationalInstitutionName,
      'gender': gender,
      'birthDate': birthDate,
    });
    if (submitDelay != null) await Future<void>.delayed(submitDelay!);
    if (submitError != null) throw submitError!;
    return const CompleteCustomerProfileResult(
      alreadyCompleted: false,
      organizationId: 'org-1',
    );
  }

  @override
  Future<CustomerProfileCompletionResult> getCompletionState() async {
    completionStateCalls += 1;
    if (completionStateError != null) throw completionStateError!;
    // Defaults to incomplete — matches every existing test's expectation
    // that the form renders by default (mirrors the old fake repository's
    // default "no customer doc yet" behavior).
    return const CustomerProfileCompletionResult(isComplete: false);
  }
}

/// CR.1.2 — a minimal fake; these screen-level tests only ever reach Step
/// 2's idle state (via "Şimdilik Geç"), never actually attempt an upload —
/// the full pick/upload/retry/quota matrix lives in
/// `step2_photo_step_test.dart`. `watchGallery` returns an empty gallery
/// (quota never full); the two write-path methods are never expected to
/// be called from these tests.
class _FakeCustomerPhotoGateway implements CustomerPhotoGateway {
  const _FakeCustomerPhotoGateway();

  @override
  Stream<List<CustomerPhoto>> watchGallery({
    required String organizationId,
    required String customerId,
  }) =>
      Stream.value(const []);

  @override
  Future<CustomerPhotoUploadGrant> requestUploadGrant({
    required String organizationId,
    required String contentType,
    String? purpose,
  }) =>
      throw UnimplementedError('not exercised by these screen-level tests');

  @override
  Future<void> selectProfilePhoto({
    required String organizationId,
    required String photoId,
  }) =>
      throw UnimplementedError('not exercised by these screen-level tests');

  @override
  Stream<String?> watchSelectedProfilePhotoRef({
    required String organizationId,
    required String customerId,
  }) =>
      Stream.value(null);
}

class _FakeCustomerPhotoStorageClient implements CustomerPhotoStorageClient {
  const _FakeCustomerPhotoStorageClient();

  @override
  Future<void> uploadBytes({
    required String objectPath,
    required Uint8List bytes,
    required String contentType,
  }) =>
      throw UnimplementedError('not exercised by these screen-level tests');

  @override
  Future<Uint8List?> downloadBytes(String objectPath) async => null;
}

class _FakeCustomerPhotoPicker implements CustomerPhotoPicker {
  const _FakeCustomerPhotoPicker();

  @override
  Future<PickedCustomerPhoto?> pickImage({
    required CustomerPhotoPickSource source,
  }) =>
      throw UnimplementedError('not exercised by these screen-level tests');
}
