import 'package:abakus_one_v2/core/utils/clock_provider.dart';
import 'package:abakus_one_v2/features/feedback/data/customer_feedback_repository.dart';
import 'package:abakus_one_v2/features/feedback/domain/customer_feedback.dart';
import 'package:abakus_one_v2/features/feedback/presentation/providers/feedback_dependencies_provider.dart';
import 'package:abakus_one_v2/features/feedback/presentation/screens/customer_feedback_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';

/// Always throws — used to prove a repository failure never reaches the UI
/// as a raw exception `toString()` (customer-side closure audit finding).
class _ThrowingCustomerFeedbackRepository
    implements CustomerFeedbackRepository {
  @override
  Future<void> append(CustomerFeedback feedback) async {
    throw StateError('simulated repository failure');
  }

  @override
  Future<CustomerFeedback?> findById(String feedbackId) async => null;

  @override
  Future<List<CustomerFeedback>> findByBranchId(String branchId) async => [];

  @override
  Future<List<CustomerFeedback>> findByCustomerId(String customerId) async =>
      [];
}

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(FakeClock(DateTime(2026, 1, 1))),
          ...overrides,
        ],
        child: const MaterialApp(
          home: CustomerFeedbackScreen(branchId: 'branch-1'),
        ),
      ),
    );
  }

  testWidgets('shows the compose form', (tester) async {
    await pumpScreen(tester);
    await tester.pump();

    expect(find.text('Geri Bildirim'), findsOneWidget);
    expect(find.text('Gönder'), findsOneWidget);
  });

  testWidgets('submitting with an empty subject shows an inline error',
      (tester) async {
    await pumpScreen(tester);
    await tester.pump();

    await tester.tap(find.text('Gönder'));
    await tester.pump();

    expect(find.text('Konu boş olamaz.'), findsOneWidget);
  });

  testWidgets('a full submission shows the thank-you state', (tester) async {
    await pumpScreen(tester);
    await tester.pump();

    await tester.enterText(
        find.widgetWithText(TextField, 'Konu'), 'Sipariş gecikti');
    await tester.enterText(
        find.widgetWithText(TextField, 'Mesaj'), 'Siparişim çok geç geldi.');
    await tester.tap(find.text('Gönder'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
        find.text('Geri bildiriminiz için teşekkür ederiz.'), findsOneWidget);
  });

  testWidgets(
      'a repository failure shows the mapped Turkish message, never a raw exception toString()',
      (tester) async {
    await pumpScreen(
      tester,
      overrides: [
        customerFeedbackRepositoryProvider
            .overrideWithValue(_ThrowingCustomerFeedbackRepository()),
      ],
    );
    await tester.pump();

    await tester.enterText(
        find.widgetWithText(TextField, 'Konu'), 'Sipariş gecikti');
    await tester.enterText(
        find.widgetWithText(TextField, 'Mesaj'), 'Siparişim çok geç geldi.');
    await tester.tap(find.text('Gönder'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Beklenmeyen bir hata oluştu.'), findsOneWidget);
    expect(find.textContaining('StateError'), findsNothing);
    expect(find.textContaining('Instance of'), findsNothing);
  });
}
