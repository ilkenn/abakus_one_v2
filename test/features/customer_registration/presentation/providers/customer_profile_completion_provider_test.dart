import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/customer_registration/data/customer_registration_gateway.dart';
import 'package:abakus_one_v2/features/customer_registration/domain/models/customer_gender.dart';
import 'package:abakus_one_v2/features/customer_registration/domain/models/customer_profile_completion_state.dart';
import 'package:abakus_one_v2/features/customer_registration/domain/models/occupation_status.dart';
import 'package:abakus_one_v2/features/customer_registration/presentation/providers/customer_registration_providers.dart';

/// Customer Registration CR.1 security fix (2026-08-19) — the completion
/// state is now resolved via the server-authoritative
/// `getCustomerProfileCompletionState` callable, never a direct client
/// read of `customers`/`tenantCustomers` (the latter is structurally
/// unreadable by an ordinary customer — see the gateway's own doc
/// comment). These tests use a fake gateway, not a fake Firestore
/// repository — the whole point of this fix is that Firestore is never
/// touched by this feature for this purpose any more.
void main() {
  AuthState realCustomerState({String uid = 'customer-uid-1'}) {
    return AuthState(
      isAuthenticated: true,
      isGuest: false,
      session: AuthSession(
        uid: uid,
        phoneNumber: '+905551234567',
        createdAt: DateTime(2026, 1, 1),
        expiresAt: DateTime(2027, 1, 1),
      ),
    );
  }

  ProviderContainer buildContainer({
    AuthState? authState,
    required _FakeCustomerRegistrationGateway gateway,
  }) {
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          () => SeededAuthNotifier(authState ?? realCustomerState()),
        ),
        customerRegistrationGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test(
      'a guest session never calls the gateway — treated as complete, the gate never applies',
      () async {
    final gateway = _FakeCustomerRegistrationGateway();
    final container = buildContainer(
      authState: const AuthState(isAuthenticated: false, isGuest: true),
      gateway: gateway,
    );

    final state = container.read(customerProfileCompletionStateProvider);

    expect(state.phase, CustomerProfileCompletionPhase.complete);
    expect(gateway.completionStateCalls, 0);
  });

  test('an unauthenticated session never calls the gateway either', () async {
    final gateway = _FakeCustomerRegistrationGateway();
    final container = buildContainer(
      authState: const AuthState(isAuthenticated: false, isGuest: false),
      gateway: gateway,
    );

    final state = container.read(customerProfileCompletionStateProvider);

    expect(state.phase, CustomerProfileCompletionPhase.complete);
    expect(gateway.completionStateCalls, 0);
  });

  test(
      'a first-time customer (gateway resolves incomplete) is routed as incomplete, not error',
      () async {
    final gateway = _FakeCustomerRegistrationGateway(
      result: const CustomerProfileCompletionResult(
        isComplete: false,
        reason: 'customerMissing',
      ),
    );
    final container = buildContainer(gateway: gateway);

    final state =
        await container.read(customerProfileCompletionResultProvider.future);
    final completionState =
        container.read(customerProfileCompletionStateProvider);

    expect(state.isComplete, isFalse);
    expect(completionState.phase, CustomerProfileCompletionPhase.incomplete);
  });

  test('a fully complete customer resolves to complete', () async {
    final gateway = _FakeCustomerRegistrationGateway(
      result: const CustomerProfileCompletionResult(isComplete: true),
    );
    final container = buildContainer(gateway: gateway);

    await container.read(customerProfileCompletionResultProvider.future);
    final completionState =
        container.read(customerProfileCompletionStateProvider);

    expect(completionState.phase, CustomerProfileCompletionPhase.complete);
  });

  test(
      'a real backend/permission failure resolves to error, never silently to incomplete — fails closed',
      () async {
    final gateway = _FakeCustomerRegistrationGateway(
      error: const CustomerRegistrationGatewayException(
        'permission-denied',
        'boom',
      ),
    );
    final container = buildContainer(gateway: gateway);

    // Await the underlying future's completion (with its error) before
    // reading the derived state, since AsyncValue only reflects settled
    // results.
    await container
        .read(customerProfileCompletionResultProvider.future)
        .catchError(
            (_) => const CustomerProfileCompletionResult(isComplete: false));
    final completionState =
        container.read(customerProfileCompletionStateProvider);

    expect(completionState.phase, CustomerProfileCompletionPhase.error);
  });

  test('loading is the state before the callable resolves', () {
    final gateway = _FakeCustomerRegistrationGateway(
      result: const CustomerProfileCompletionResult(isComplete: true),
      delay: const Duration(milliseconds: 50),
    );
    final container = buildContainer(gateway: gateway);

    final completionState =
        container.read(customerProfileCompletionStateProvider);

    expect(completionState.phase, CustomerProfileCompletionPhase.loading);
  });

  test(
      'invalidating customerProfileCompletionResultProvider triggers a fresh callable call — no polling, an explicit refresh only',
      () async {
    final gateway = _FakeCustomerRegistrationGateway(
      result: const CustomerProfileCompletionResult(isComplete: false),
    );
    final container = buildContainer(gateway: gateway);

    await container.read(customerProfileCompletionResultProvider.future);
    expect(gateway.completionStateCalls, 1);

    gateway.result = const CustomerProfileCompletionResult(isComplete: true);
    container.invalidate(customerProfileCompletionResultProvider);
    await container.read(customerProfileCompletionResultProvider.future);

    expect(gateway.completionStateCalls, 2);
    expect(
      container.read(customerProfileCompletionStateProvider).phase,
      CustomerProfileCompletionPhase.complete,
    );
  });
}

class _FakeCustomerRegistrationGateway implements CustomerRegistrationGateway {
  _FakeCustomerRegistrationGateway({
    this.result = const CustomerProfileCompletionResult(isComplete: false),
    this.error,
    this.delay,
  });

  CustomerProfileCompletionResult result;
  final CustomerRegistrationGatewayException? error;
  final Duration? delay;
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
    return const CompleteCustomerProfileResult(
      alreadyCompleted: false,
      organizationId: 'org-1',
    );
  }

  @override
  Future<CustomerProfileCompletionResult> getCompletionState() async {
    completionStateCalls += 1;
    if (delay != null) await Future<void>.delayed(delay!);
    if (error != null) throw error!;
    return result;
  }
}
