import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/admin/data/staff_auth_repository.dart';
import 'package:abakus_one_v2/features/admin/presentation/providers/admin_dependencies_provider.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/admin_shell_screen.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/admin_unauthorized_screen.dart';
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
  _ScriptedStaffAuthRepository(
    this._script, {
    List<Future<String> Function()>? phoneStartScript,
    List<Future<ActorSession?> Function()>? phoneCompleteScript,
  })  : _phoneStartScript = phoneStartScript,
        _phoneCompleteScript = phoneCompleteScript;
  final List<Future<ActorSession?> Function()> _script;
  final List<Future<String> Function()>? _phoneStartScript;
  final List<Future<ActorSession?> Function()>? _phoneCompleteScript;
  int callCount = 0;
  String? lastEmail;
  String? lastPassword;
  String? lastPhoneNumber;
  String? lastVerificationId;
  String? lastSmsCode;
  int signOutCallCount = 0;
  int phoneStartCallCount = 0;
  int phoneCompleteCallCount = 0;

  /// Records `'signOut'`/`'signIn'` in call order — used to prove a stale
  /// session is cleared BEFORE the new sign-in attempt, not merely that
  /// both happened at some point.
  final List<String> callOrder = [];

  @override
  Future<ActorSession?> signIn({
    required String email,
    required String password,
  }) {
    callOrder.add('signIn');
    lastEmail = email;
    lastPassword = password;
    final step = _script[callCount.clamp(0, _script.length - 1)];
    callCount++;
    return step();
  }

  @override
  Future<String> startPhoneSignIn(String phoneNumber) {
    callOrder.add('startPhoneSignIn');
    lastPhoneNumber = phoneNumber;
    final script = _phoneStartScript;
    if (script == null) {
      throw UnimplementedError('No phoneStartScript configured for this test.');
    }
    final step = script[phoneStartCallCount.clamp(0, script.length - 1)];
    phoneStartCallCount++;
    return step();
  }

  @override
  Future<ActorSession?> completePhoneSignIn({
    required String verificationId,
    required String smsCode,
  }) {
    callOrder.add('completePhoneSignIn');
    lastVerificationId = verificationId;
    lastSmsCode = smsCode;
    final script = _phoneCompleteScript;
    if (script == null) {
      throw UnimplementedError(
          'No phoneCompleteScript configured for this test.');
    }
    final step = script[phoneCompleteCallCount.clamp(0, script.length - 1)];
    phoneCompleteCallCount++;
    return step();
  }

  @override
  Future<ActorSession?> refreshSession(ActorSession current) async => current;

  @override
  Future<void> signOut() async {
    callOrder.add('signOut');
    signOutCallCount++;
  }
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

  testWidgets(
      'a stale session (customer or different staff) left over from '
      'before is cleared (signOut) BEFORE the new sign-in attempt — closes '
      'the real-world "[cloud_firestore/permission-denied]" this session\'s '
      'own PC Yönetici İnceleme Modu report found on Chrome', (tester) async {
    final repository = _ScriptedStaffAuthRepository([() async => _session]);
    await _pump(tester, repository);
    await _fillAndSubmit(tester);
    await tester.pump(const Duration(milliseconds: 50));

    expect(repository.signOutCallCount, 1);
    expect(repository.callOrder, ['signOut', 'signIn'],
        reason: 'signOut must complete before signIn is attempted, not '
            'merely happen at some point');
  });

  testWidgets(
      'PC Yönetici İnceleme Modu: the dev-admin shortcut submits the real '
      'seed_dev_staff.mjs credentials through the same _signIn() path — '
      'never a fabricated session — and reaches the real Admin shell',
      (tester) async {
    final repository = _ScriptedStaffAuthRepository([() async => _session]);
    await _pump(tester, repository);

    final button = find.widgetWithText(
        OutlinedButton, 'Dev Admin ile Gir (Yalnızca Development)');
    expect(button, findsOneWidget,
        reason: 'flutter test always runs debug + AppEnvironment.development, '
            'so the shortcut must be visible here');

    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repository.callCount, 1);
    expect(repository.lastEmail, 'admin@abakus.dev');
    expect(repository.lastPassword, 'abakus-dev-admin-2026');
    expect(find.byType(AdminShellScreen), findsOneWidget);
    expect(
      tester
          .widget<AdminShellScreen>(find.byType(AdminShellScreen))
          .initialNavItemId,
      'pos',
      reason: 'the dev-admin shortcut must land directly on the POS branch '
          'overview, never the shell\'s general default landing item',
    );
  });

  group('phone sign-in', () {
    Future<void> switchToPhone(WidgetTester tester) async {
      await tester.tap(find.text('Telefon'));
      await tester.pump();
    }

    testWidgets(
        'the phone toggle switches to the phone form, hiding the email '
        'fields entirely', (tester) async {
      await _pump(tester, _ScriptedStaffAuthRepository([]));
      await switchToPhone(tester);

      expect(find.widgetWithText(TextFormField, 'E-posta'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Şifre'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Telefon Numarası'),
          findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Kod Gönder'), findsOneWidget);
    });

    testWidgets(
        'an invalid phone number shows a validation error and never calls '
        'startPhoneSignIn', (tester) async {
      final repository = _ScriptedStaffAuthRepository([]);
      await _pump(tester, repository);
      await switchToPhone(tester);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Telefon Numarası'), '123');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Kod Gönder'));
      await tester.pump();

      expect(repository.phoneStartCallCount, 0);
      expect(find.textContaining('Geçerli bir telefon numarası girin'),
          findsOneWidget);
    });

    testWidgets(
        'sending a code signs out any stale session first, normalizes the '
        'number to +90, calls startPhoneSignIn, and shows the code-entry '
        'step on success', (tester) async {
      final repository = _ScriptedStaffAuthRepository(
        [],
        phoneStartScript: [() async => 'verification-id-1'],
      );
      await _pump(tester, repository);
      await switchToPhone(tester);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Telefon Numarası'), '5337106414');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Kod Gönder'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(repository.callOrder, ['signOut', 'startPhoneSignIn']);
      expect(repository.lastPhoneNumber, '+905337106414');
      expect(
          find.widgetWithText(TextFormField, 'Doğrulama Kodu'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Doğrula ve Giriş Yap'),
          findsOneWidget);
      expect(
          find.widgetWithText(TextFormField, 'Telefon Numarası'), findsNothing);
    });

    testWidgets(
        'a StaffAuthUnavailableException from startPhoneSignIn shows its '
        'message and stays on the number-entry step', (tester) async {
      final repository = _ScriptedStaffAuthRepository(
        [],
        phoneStartScript: [
          () => Future<String>.error(const StaffAuthUnavailableException(
              'Kod gönderilemedi (zaman aşımı) — tekrar deneyin.')),
        ],
      );
      await _pump(tester, repository);
      await switchToPhone(tester);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Telefon Numarası'), '5337106414');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Kod Gönder'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Kod gönderilemedi (zaman aşımı) — tekrar deneyin.'),
          findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Telefon Numarası'),
          findsOneWidget,
          reason: 'a failed send must not advance to the code-entry step');
    });

    testWidgets(
        'verifying the right code calls completePhoneSignIn with the '
        'entered code and verificationId, and reaches the real Admin '
        'shell on success', (tester) async {
      final repository = _ScriptedStaffAuthRepository(
        [],
        phoneStartScript: [() async => 'verification-id-1'],
        phoneCompleteScript: [() async => _session],
      );
      await _pump(tester, repository);
      await switchToPhone(tester);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Telefon Numarası'), '5337106414');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Kod Gönder'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Doğrulama Kodu'), '123456');
      await tester
          .tap(find.widgetWithText(ElevatedButton, 'Doğrula ve Giriş Yap'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(repository.lastVerificationId, 'verification-id-1');
      expect(repository.lastSmsCode, '123456');
      expect(find.byType(AdminShellScreen), findsOneWidget);
      // Guards against the real regression this test originally missed:
      // `AdminShellScreen` mounts either way, but renders
      // `AdminUnauthorizedScreen` instead of its real content whenever
      // `actorSessionProvider` wasn't actually populated — exactly what
      // happened when the phone path bypassed `StaffSessionController` and
      // called `StaffAuthRepository` directly.
      expect(find.byType(AdminUnauthorizedScreen), findsNothing);
    });

    testWidgets(
        'an invalid code (completePhoneSignIn returns null) shows the '
        'invalid-credential message, never reaching the Admin shell',
        (tester) async {
      final repository = _ScriptedStaffAuthRepository(
        [],
        phoneStartScript: [() async => 'verification-id-1'],
        phoneCompleteScript: [() async => null],
      );
      await _pump(tester, repository);
      await switchToPhone(tester);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Telefon Numarası'), '5337106414');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Kod Gönder'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Doğrulama Kodu'), '000000');
      await tester
          .tap(find.widgetWithText(ElevatedButton, 'Doğrula ve Giriş Yap'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(AdminShellScreen), findsNothing);
      expect(find.text('Giriş başarısız. Bilgilerinizi kontrol edin.'),
          findsOneWidget);
    });

    testWidgets(
        '"Numarayı Değiştir" resets back to the number-entry step, '
        'clearing the error', (tester) async {
      final repository = _ScriptedStaffAuthRepository(
        [],
        phoneStartScript: [() async => 'verification-id-1'],
      );
      await _pump(tester, repository);
      await switchToPhone(tester);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Telefon Numarası'), '5337106414');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Kod Gönder'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.widgetWithText(TextButton, 'Numarayı Değiştir'));
      await tester.pump();

      expect(find.widgetWithText(TextFormField, 'Telefon Numarası'),
          findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Kod Gönder'), findsOneWidget);
    });
  });
}
