import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/auth/presentation/screens/login_screen.dart';
import 'package:abakus_one_v2/features/admin/domain/organization/branch.dart';
import 'package:abakus_one_v2/features/admin/domain/organization/branch_status.dart';
import 'package:abakus_one_v2/features/menu/presentation/screens/menu_screen.dart';
import 'package:abakus_one_v2/features/takeaway/application/use_cases/list_takeaway_eligible_branches.dart';
import 'package:abakus_one_v2/features/takeaway/presentation/providers/takeaway_dependencies_provider.dart';
import 'package:abakus_one_v2/features/takeaway/presentation/screens/takeaway_branch_selection_screen.dart';

Branch _branch(String id, String name) {
  return Branch(
    id: id,
    restaurantId: 'restaurant-1',
    name: name,
    status: BranchStatus.active,
    supportedOrderChannelIds: const {'takeaway'},
    createdAt: DateTime(2026, 1, 1),
    revision: 1,
  );
}

Future<ProviderContainer> pumpScreen(
  WidgetTester tester, {
  required AuthState authState,
  List<TakeawayEligibleBranch> branches = const [],
}) async {
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(() => SeededAuthNotifier(authState)),
      takeawayEligibleBranchesProvider.overrideWith((ref) async => branches),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: TakeawayBranchSelectionScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets(
      'giriş yapılmamışsa Giriş Yap istemi gösterilir, şube listesi '
      'gösterilmez', (tester) async {
    await pumpScreen(
      tester,
      authState: const AuthState(isAuthenticated: false, isGuest: true),
      branches: [TakeawayEligibleBranch(_branch('branch-1', 'Ortaköy'))],
    );

    expect(find.text('Giriş Yap'), findsOneWidget);
    expect(find.text('Ortaköy'), findsNothing);
  });

  testWidgets('Giriş Yap dokunulunca LoginScreen açılır', (tester) async {
    await pumpScreen(
      tester,
      authState: const AuthState(isAuthenticated: false, isGuest: true),
    );

    await tester.tap(find.text('Giriş Yap'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets(
      'anonymous/guest oturum de "giriş gerekli" olarak kabul edilir '
      '(isAuthenticated true ama isGuest true olsa bile)', (tester) async {
    await pumpScreen(
      tester,
      authState: AuthState(
        isAuthenticated: true,
        isGuest: true,
        session: AuthSession(
          uid: 'anon-uid',
          phoneNumber: '',
          createdAt: DateTime(2026, 8, 1),
          expiresAt: DateTime(2027, 8, 1),
        ),
      ),
    );

    expect(find.text('Giriş Yap'), findsOneWidget);
  });

  testWidgets(
      'gerçek, süresi dolmamış müşteri oturumunda uygun şubeler '
      'listelenir', (tester) async {
    await pumpScreen(
      tester,
      authState: AuthState(
        isAuthenticated: true,
        isGuest: false,
        session: AuthSession(
          uid: 'real-customer-uid',
          phoneNumber: '+905551234567',
          createdAt: DateTime(2026, 8, 1),
          expiresAt: DateTime(2027, 8, 1),
        ),
      ),
      branches: [TakeawayEligibleBranch(_branch('branch-1', 'Ortaköy'))],
    );

    expect(find.text('Giriş Yap'), findsNothing);
    expect(find.text('Ortaköy'), findsOneWidget);
  });

  testWidgets('süresi dolmuş oturum "giriş gerekli" olarak kabul edilir', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      authState: AuthState(
        isAuthenticated: true,
        isGuest: false,
        session: AuthSession(
          uid: 'real-customer-uid',
          phoneNumber: '+905551234567',
          createdAt: DateTime(2025, 1, 1),
          expiresAt: DateTime(2025, 1, 2),
        ),
      ),
    );

    expect(find.text('Giriş Yap'), findsOneWidget);
  });

  testWidgets('uygun şube yoksa boş durum gösterilir', (tester) async {
    await pumpScreen(
      tester,
      authState: AuthState(
        isAuthenticated: true,
        isGuest: false,
        session: AuthSession(
          uid: 'real-customer-uid',
          phoneNumber: '+905551234567',
          createdAt: DateTime(2026, 8, 1),
          expiresAt: DateTime(2027, 8, 1),
        ),
      ),
      branches: const [],
    );

    expect(
      find.textContaining('Gel Al siparişi kabul eden bir şube yok'),
      findsOneWidget,
    );
  });

  testWidgets('bir şube seçilince MenuScreen\'e geçilir', (tester) async {
    await pumpScreen(
      tester,
      authState: AuthState(
        isAuthenticated: true,
        isGuest: false,
        session: AuthSession(
          uid: 'real-customer-uid',
          phoneNumber: '+905551234567',
          createdAt: DateTime(2026, 8, 1),
          expiresAt: DateTime(2027, 8, 1),
        ),
      ),
      branches: [TakeawayEligibleBranch(_branch('branch-1', 'Ortaköy'))],
    );

    await tester.tap(find.text('Ortaköy'));
    await tester.pumpAndSettle();

    expect(find.byType(MenuScreen), findsOneWidget);
  });
}
