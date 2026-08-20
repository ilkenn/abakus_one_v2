import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/customer_registration/data/customer_registration_gateway.dart';
import 'package:abakus_one_v2/features/customer_registration/domain/models/customer_gender.dart';
import 'package:abakus_one_v2/features/customer_registration/domain/models/occupation_status.dart';
import 'package:abakus_one_v2/features/customer_registration/presentation/providers/customer_registration_providers.dart';
import 'package:abakus_one_v2/features/customer_registration/presentation/providers/customer_registration_submit_provider.dart';

void main() {
  ProviderContainer buildContainer(_FakeCustomerRegistrationGateway gateway) {
    final container = ProviderContainer(
      overrides: [
        customerRegistrationGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<bool> submit(
    ProviderContainer container, {
    String firstName = 'Ayşe',
    String lastName = 'Yılmaz',
    String email = 'ayse@example.com',
    OccupationStatus occupationStatus = OccupationStatus.other,
    DateTime? birthDate,
  }) {
    return container.read(customerRegistrationSubmitProvider.notifier).submit(
          firstName: firstName,
          lastName: lastName,
          email: email,
          occupationStatus: occupationStatus,
          gender: CustomerGender.preferNotToSay,
          birthDate: birthDate ?? DateTime(1990, 8, 20),
        );
  }

  test(
      'a successful submit returns true and leaves the state idle — never navigates itself',
      () async {
    final gateway = _FakeCustomerRegistrationGateway();
    final container = buildContainer(gateway);

    final success = await submit(container);

    expect(success, isTrue);
    expect(container.read(customerRegistrationSubmitProvider).phase,
        CustomerRegistrationSubmitPhase.idle);
    expect(gateway.calls, hasLength(1));
  });

  test(
      'CR.1.2 — a successful submit() does NOT invalidate the completion-state '
      'provider — that refresh is deferred to finishOnboarding(), once the '
      'optional Step 2 photo step finishes or is skipped', () async {
    final gateway = _FakeCustomerRegistrationGateway();
    final container = ProviderContainer(
      overrides: [
        customerRegistrationGatewayProvider.overrideWithValue(gateway),
        authProvider.overrideWith(
          () => SeededAuthNotifier(
            AuthState(
              isAuthenticated: true,
              isGuest: false,
              session: AuthSession(
                uid: 'customer-uid-1',
                phoneNumber: '+905551234567',
                createdAt: DateTime(2026, 1, 1),
                expiresAt: DateTime(2027, 1, 1),
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Establish the provider before submitting, exactly like the router/
    // screen would.
    await container.read(customerProfileCompletionResultProvider.future);
    expect(gateway.completionStateCalls, 1);

    await submit(container);

    // Step 1 alone must never trigger a re-fetch — the screen must stay
    // on /complete-profile long enough to offer Step 2. Reading the
    // already-resolved future again resolves synchronously without a new
    // callable call, proving no invalidate happened.
    await container.read(customerProfileCompletionResultProvider.future);
    expect(gateway.completionStateCalls, 1);
  });

  test(
      'CR.1.2 — finishOnboarding() is the ONE re-fetch trigger — invalidates/'
      'refreshes the server-authoritative completion-state provider', () async {
    final gateway = _FakeCustomerRegistrationGateway();
    final container = ProviderContainer(
      overrides: [
        customerRegistrationGatewayProvider.overrideWithValue(gateway),
        authProvider.overrideWith(
          () => SeededAuthNotifier(
            AuthState(
              isAuthenticated: true,
              isGuest: false,
              session: AuthSession(
                uid: 'customer-uid-1',
                phoneNumber: '+905551234567',
                createdAt: DateTime(2026, 1, 1),
                expiresAt: DateTime(2027, 1, 1),
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(customerProfileCompletionResultProvider.future);
    expect(gateway.completionStateCalls, 1);

    await submit(container);
    container
        .read(customerRegistrationSubmitProvider.notifier)
        .finishOnboarding();

    await container.read(customerProfileCompletionResultProvider.future);
    expect(gateway.completionStateCalls, 2);
  });

  test('a duplicate near-simultaneous submit never sends two callable requests',
      () async {
    final gateway = _FakeCustomerRegistrationGateway();
    final container = buildContainer(gateway);
    final notifier =
        container.read(customerRegistrationSubmitProvider.notifier);

    final results = await Future.wait([
      notifier.submit(
        firstName: 'Ayşe',
        lastName: 'Yılmaz',
        email: 'ayse@example.com',
        occupationStatus: OccupationStatus.other,
        gender: CustomerGender.preferNotToSay,
        birthDate: DateTime(1990, 8, 20),
      ),
      notifier.submit(
        firstName: 'Ayşe',
        lastName: 'Yılmaz',
        email: 'ayse@example.com',
        occupationStatus: OccupationStatus.other,
        gender: CustomerGender.preferNotToSay,
        birthDate: DateTime(1990, 8, 20),
      ),
    ]);

    expect(results.where((r) => r).length, 1,
        reason: 'exactly one of the two calls actually proceeds');
    expect(gateway.calls, hasLength(1));
  });

  test(
      'a gateway invalid-argument failure maps to the invalid-input message, not the generic one',
      () async {
    final gateway = _FakeCustomerRegistrationGateway(
      error: const CustomerRegistrationGatewayException(
          'invalid-argument', 'email invalid'),
    );
    final container = buildContainer(gateway);

    final success = await submit(container);

    expect(success, isFalse);
    final state = container.read(customerRegistrationSubmitProvider);
    expect(state.phase, CustomerRegistrationSubmitPhase.failed);
    expect(state.errorMessage, contains('bilgileri'));
  });

  test('a generic gateway failure maps to the generic failure message',
      () async {
    final gateway = _FakeCustomerRegistrationGateway(
      error: const CustomerRegistrationGatewayException('unknown', 'boom'),
    );
    final container = buildContainer(gateway);

    final success = await submit(container);

    expect(success, isFalse);
    final state = container.read(customerRegistrationSubmitProvider);
    expect(state.errorMessage, isNot(contains('bilgileri')));
  });

  test('dismissError resets back to idle', () async {
    final gateway = _FakeCustomerRegistrationGateway(
      error: const CustomerRegistrationGatewayException('unknown', 'boom'),
    );
    final container = buildContainer(gateway);
    await submit(container);
    expect(container.read(customerRegistrationSubmitProvider).phase,
        CustomerRegistrationSubmitPhase.failed);

    container.read(customerRegistrationSubmitProvider.notifier).dismissError();

    expect(container.read(customerRegistrationSubmitProvider).phase,
        CustomerRegistrationSubmitPhase.idle);
    expect(container.read(customerRegistrationSubmitProvider).errorMessage,
        isNull);
  });

  test(
      'email is normalized (trimmed/lowercased) before being sent to the gateway',
      () async {
    final gateway = _FakeCustomerRegistrationGateway();
    final container = buildContainer(gateway);

    await submit(container, email: '  Ayse.Yilmaz@EXAMPLE.com  ');

    expect(gateway.calls.single['email'], 'ayse.yilmaz@example.com');
  });

  test(
      'working occupationStatus passes workplaceName through; student/other pass null for it',
      () async {
    final gateway = _FakeCustomerRegistrationGateway();
    final container = buildContainer(gateway);

    await container.read(customerRegistrationSubmitProvider.notifier).submit(
          firstName: 'Ayşe',
          lastName: 'Yılmaz',
          email: 'ayse@example.com',
          occupationStatus: OccupationStatus.working,
          workplaceName: 'Abaküs Kahve',
          gender: CustomerGender.female,
          birthDate: DateTime(1990, 8, 20),
        );

    expect(gateway.calls.single['workplaceName'], 'Abaküs Kahve');
  });

  test(
      'birthDate is normalized to the canonical YYYY-MM-DD string before being sent to the gateway — never a raw DateTime',
      () async {
    final gateway = _FakeCustomerRegistrationGateway();
    final container = buildContainer(gateway);

    await submit(container, birthDate: DateTime(1990, 8, 20));

    expect(gateway.calls.single['birthDate'], '1990-08-20');
  });
}

class _FakeCustomerRegistrationGateway implements CustomerRegistrationGateway {
  _FakeCustomerRegistrationGateway({this.error});

  final CustomerRegistrationGatewayException? error;
  final List<Map<String, dynamic>> calls = [];
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
    calls.add({
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'occupationStatus': occupationStatus,
      'workplaceName': workplaceName,
      'educationalInstitutionName': educationalInstitutionName,
      'gender': gender,
      'birthDate': birthDate,
    });
    if (error != null) throw error!;
    return const CompleteCustomerProfileResult(
      alreadyCompleted: false,
      organizationId: 'org-1',
    );
  }

  @override
  Future<CustomerProfileCompletionResult> getCompletionState() async {
    completionStateCalls += 1;
    return const CustomerProfileCompletionResult(isComplete: false);
  }
}
