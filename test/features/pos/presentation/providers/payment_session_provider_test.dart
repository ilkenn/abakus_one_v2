import 'package:abakus_one_v2/core/utils/clock_provider.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/application/errors/payment_application_error.dart';
import 'package:abakus_one_v2/features/pos/data/payment_session_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/models/payment_session_status.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/payment_session_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/payment_session_provider.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_method_seed_data.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';

void main() {
  late FakeClock clock;
  late InMemoryPaymentSessionRepository repository;
  late ProviderContainer container;

  ProviderContainer buildContainer() {
    clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
    repository = InMemoryPaymentSessionRepository();
    return ProviderContainer(
      overrides: [
        clockProvider.overrideWithValue(clock),
        paymentSessionRepositoryProvider.overrideWithValue(repository),
      ],
    );
  }

  void startSession(ProviderContainer c, {Money? total}) {
    c.read(paymentSessionProvider.notifier).startSession(
          sessionId: 'ps1',
          orderId: OrderId('order-1'),
          totalAmount: total ?? Money.fromWhole(645, Currency.tryLira),
        );
  }

  setUp(() {
    container = buildContainer();
  });

  tearDown(() {
    container.dispose();
  });

  group('PaymentSessionController — idle/start', () {
    test('build() starts idle with no session', () {
      final state = container.read(paymentSessionProvider);
      expect(state.isIdle, isTrue);
    });

    test('startSession persists revision 1 and moves out of idle', () {
      startSession(container);
      final state = container.read(paymentSessionProvider);

      expect(state.isIdle, isFalse);
      expect(state.session!.revision, 1);
      expect(state.session!.status, PaymentSessionStatus.collecting);
      expect(repository.allRevisions, hasLength(1));
    });
  });

  group('PaymentSessionController — splits', () {
    test('addSplit persists the new revision and stays collecting', () async {
      startSession(container);
      final notifier = container.read(paymentSessionProvider.notifier);

      await notifier.addSplit(
          method: PaymentMethodSeedData.cash,
          amount: Money.fromWhole(200, Currency.tryLira));

      final state = container.read(paymentSessionProvider);
      expect(state.session!.splits, hasLength(1));
      expect(state.session!.status, PaymentSessionStatus.collecting);
    });

    test('adding a fully-settling cash split reaches readyToComplete',
        () async {
      startSession(container);
      final notifier = container.read(paymentSessionProvider.notifier);

      await notifier.addSplit(
          method: PaymentMethodSeedData.cash,
          amount: Money.fromWhole(645, Currency.tryLira));

      final state = container.read(paymentSessionProvider);
      expect(state.session!.status, PaymentSessionStatus.readyToComplete);
    });

    test(
        'a rejected non-cash overpay surfaces a validation error, session preserved',
        () async {
      startSession(container);
      final notifier = container.read(paymentSessionProvider.notifier);

      await notifier.addSplit(
        method: PaymentMethodSeedData.creditCard,
        amount: Money.fromWhole(1000, Currency.tryLira),
      );

      final state = container.read(paymentSessionProvider);
      expect(state.error, isA<PaymentValidationError>());
      expect(state.session!.splits, isEmpty);
    });

    test('removeSplit removes a split and drops back to collecting', () async {
      startSession(container);
      final notifier = container.read(paymentSessionProvider.notifier);
      await notifier.addSplit(
          method: PaymentMethodSeedData.cash,
          amount: Money.fromWhole(645, Currency.tryLira));
      final splitId =
          container.read(paymentSessionProvider).session!.splits.single.id;

      await notifier.removeSplit(splitId);

      final state = container.read(paymentSessionProvider);
      expect(state.session!.splits, isEmpty);
      expect(state.session!.status, PaymentSessionStatus.collecting);
    });
  });

  group('PaymentSessionController — complete', () {
    test('completing a fully-settled cash-only session succeeds', () async {
      startSession(container);
      final notifier = container.read(paymentSessionProvider.notifier);
      await notifier.addSplit(
          method: PaymentMethodSeedData.cash,
          amount: Money.fromWhole(645, Currency.tryLira));

      await notifier.complete();

      final state = container.read(paymentSessionProvider);
      expect(state.session!.status, PaymentSessionStatus.completed);
      expect(state.isCompleting, isFalse);
      expect(state.error, isNull);
    });

    test(
        'completing before remaining is zero fails, session preserved for retry',
        () async {
      startSession(container);
      final notifier = container.read(paymentSessionProvider.notifier);
      await notifier.addSplit(
          method: PaymentMethodSeedData.cash,
          amount: Money.fromWhole(200, Currency.tryLira));

      await notifier.complete();

      final state = container.read(paymentSessionProvider);
      expect(state.error, isA<PaymentValidationError>());
      expect(state.session!.splits, hasLength(1));
      expect(state.isCompleting, isFalse);
    });

    test(
        'a second concurrent complete call is ignored while the first is in flight',
        () async {
      startSession(container);
      final notifier = container.read(paymentSessionProvider.notifier);
      await notifier.addSplit(
          method: PaymentMethodSeedData.cash,
          amount: Money.fromWhole(645, Currency.tryLira));

      final first = notifier.complete();
      final second = notifier.complete();
      await first;
      await second;

      expect(
        repository.allRevisions
            .where((s) => s.status == PaymentSessionStatus.completed),
        hasLength(1),
      );
    });
  });

  group('PaymentSessionController — cancel', () {
    test('cancel moves the session to cancelled', () async {
      startSession(container);
      final notifier = container.read(paymentSessionProvider.notifier);

      await notifier.cancel();

      final state = container.read(paymentSessionProvider);
      expect(state.session!.status, PaymentSessionStatus.cancelled);
    });
  });
}
