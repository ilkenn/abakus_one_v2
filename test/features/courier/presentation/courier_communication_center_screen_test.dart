import 'package:abakus_one_v2/core/utils/clock_provider.dart';
import 'package:abakus_one_v2/features/courier/data/courier_message_repository.dart';
import 'package:abakus_one_v2/features/courier/presentation/providers/courier_dependencies_provider.dart';
import 'package:abakus_one_v2/features/courier/presentation/screens/courier_communication_center_screen.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/pos_authorization_policy.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/pos_authorized_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';

class _AllowAllPolicy implements PosAuthorizationPolicy {
  @override
  Future<AuthorizationResult> authorize({
    required PosAuthorizedAction action,
    required String actorStaffId,
    Map<String, String> context = const {},
  }) async =>
      const AuthorizationResult(granted: true);
}

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    CourierMessageRepository? messageRepository,
    bool withPolicy = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(FakeClock(DateTime(2026, 1, 1, 12))),
          if (messageRepository != null)
            courierMessageRepositoryProvider
                .overrideWithValue(messageRepository),
        ],
        child: MaterialApp(
          home: CourierCommunicationCenterScreen(
            branchId: 'branch-1',
            authorizationPolicy: withPolicy ? _AllowAllPolicy() : null,
          ),
        ),
      ),
    );
  }

  testWidgets('shows an empty state with no messages yet', (tester) async {
    await pumpScreen(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Henüz mesaj gönderilmedi.'), findsOneWidget);
  });

  testWidgets(
      'sending a direct message without a recipient shows an '
      'inline error', (tester) async {
    await pumpScreen(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.enterText(find.byType(TextField).last, 'Merhaba');
    await tester.tap(find.text('Gönder'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Doğrudan mesaj için kurye seçin.'), findsOneWidget);
  });

  testWidgets('a ready-message chip fills the message field', (tester) async {
    await pumpScreen(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Teslimatı tamamladım.').first);
    await tester.pump();

    final field = tester
        .widgetList<TextField>(find.byType(TextField))
        .firstWhere((f) => f.decoration?.labelText == 'Mesaj');
    expect(field.controller?.text, 'Teslimatı tamamladım.');
  });
}
