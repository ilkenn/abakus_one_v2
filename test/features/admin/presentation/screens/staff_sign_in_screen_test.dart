import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/admin/data/staff_auth_repository.dart';
import 'package:abakus_one_v2/features/admin/presentation/providers/admin_dependencies_provider.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/admin_shell_screen.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/staff_sign_in_screen.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/actor_session.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/staff_role.dart';

/// Controls exactly what `StaffAuthRepository.signIn` does for each test —
/// the real class under test here is `StaffSignInScreen` itself: does the
/// loading state always clear, is the right message shown, does retry
/// genuinely start a fresh attempt. This is the direct regression coverage
/// for the sign-in hang this wave found and fixed (`StaffSignInScreen
/// ._signIn` previously had no `try`/`catch` around this exact call).
class _ScriptedStaffAuthRepository implements StaffAuthRepository {
  _ScriptedStaffAuthRepository(this._script);
  final List<Future<ActorSession?> Function()> _script;
  int callCount = 0;

  @override
  Future<ActorSession?> signIn({
    required String email,
    required String password,
  }) {
    final step = _script[callCount.clamp(0, _script.length - 1)];
    callCount++;
    return step();
  }

  @override
  Future<ActorSession?> refreshSession(ActorSession current) async => current;

  @override
  Future<void> signOut() async {}
}

const _session = ActorSession(
  actorId: 'staff-1',
  roles: {StaffRole.manager},
  activeRole: StaffRole.manager,
);

Future<void> _pump(
  WidgetTester tester,
  StaffAuthRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [staffAuthRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(home: StaffSignInScreen()),
    ),
  );
}

Future<void> _fillAndSubmit(WidgetTester tester) async {
  await tester.enterText(
      find.widgetWithText(TextFormField, 'E-posta'), 'kasiyer@abakus.test');
  await tester.enterText(
      find.widgetWithText(TextFormField, 'Şifre'), 'GorselKabul2026!');
  await tester.tap(find.widgetWithText(ElevatedButton, 'Giriş Yap'));
  await tester.pump();
}

void main() {
  testWidgets(
      'a network timeout during sign-in clears the loading state and shows '
      'a retryable error — never an indefinite spinner (the exact hang '
      'this wave found and fixed)', (tester) async {
    final repository = _ScriptedStaffAuthRepository([
      () => Future<ActorSession?>.error(
          const StaffAuthUnavailableException('Zaman aşımı — tekrar deneyin.')),
    ]);
    await _pump(tester, repository);
    await _fillAndSubmit(tester);
    await tester.pump(const Duration(milliseconds: 50));

    // Busy state cleared — no spinner left stuck, and a specific,
    // retry-worded error is shown (never "check your credentials," since
    // the credential was never actually evaluated).
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Zaman aşımı — tekrar deneyin.'), findsOneWidget);
    expect(
      find.widgetWithText(ElevatedButton, 'Giriş Yap'),
      findsOneWidget,
    );
    final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Giriş Yap'));
    expect(button.onPressed, isNotNull,
        reason: 'the button must be re-enabled so the user can retry');
  });

  testWidgets(
      'a genuinely unexpected exception also clears the loading state and '
      'shows a generic retryable message', (tester) async {
    final repository = _ScriptedStaffAuthRepository([
      () => Future<ActorSession?>.error(StateError('unexpected')),
    ]);
    await _pump(tester, repository);
    await _fillAndSubmit(tester);
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Beklenmeyen bir sorun oluştu — tekrar deneyin.'),
        findsOneWidget);
  });

  testWidgets(
      'after a timeout error, retry genuinely starts a fresh attempt and '
      'succeeds — proving the button is not permanently stuck disabled',
      (tester) async {
    final repository = _ScriptedStaffAuthRepository([
      () => Future<ActorSession?>.error(
          const StaffAuthUnavailableException('Zaman aşımı — tekrar deneyin.')),
      () async => _session,
    ]);
    await _pump(tester, repository);
    await _fillAndSubmit(tester);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Zaman aşımı — tekrar deneyin.'), findsOneWidget);

    // Retry — the second scripted step succeeds.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Giriş Yap'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repository.callCount, 2);
    expect(find.byType(AdminShellScreen), findsOneWidget,
        reason: 'a successful retry must reach the real Admin shell, not a '
            'stub');
  });

  testWidgets(
      'an invalid credential (signIn returns null) clears the loading '
      'state and shows the invalid-credential message, never the '
      'connectivity one', (tester) async {
    final repository = _ScriptedStaffAuthRepository([() async => null]);
    await _pump(tester, repository);
    await _fillAndSubmit(tester);
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Giriş başarısız. Bilgilerinizi kontrol edin.'),
        findsOneWidget);
  });

  testWidgets('a successful sign-in reaches the real Admin shell directly',
      (tester) async {
    final repository = _ScriptedStaffAuthRepository([() async => _session]);
    await _pump(tester, repository);
    await _fillAndSubmit(tester);
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(AdminShellScreen), findsOneWidget);
  });
}
