import 'package:abakus_one_v2/core/utils/clock_provider.dart';
import 'package:abakus_one_v2/features/crm/presentation/screens/survey_admin_screen.dart';
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
  testWidgets('shows an empty state with no surveys yet', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(FakeClock(DateTime(2026, 1, 1))),
        ],
        child: MaterialApp(
          home: SurveyAdminScreen(authorizationPolicy: _AllowAllPolicy()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Henüz anket oluşturulmadı.'), findsOneWidget);
  });
}
