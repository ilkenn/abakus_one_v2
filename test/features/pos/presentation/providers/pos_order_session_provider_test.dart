import 'package:abakus_one_v2/core/utils/clock_provider.dart';
import 'package:abakus_one_v2/features/menu/domain/models/menu_product.dart';
import 'package:abakus_one_v2/features/orders/domain/discounts/discount.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/pos/application/errors/pos_application_error.dart';
import 'package:abakus_one_v2/features/pos/data/pos_order_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/models/discount_preset_seed_data.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/pos_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/pos_order_session_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';

const _simpleProduct = MenuProduct(
  id: 'prod_ayran',
  categoryId: 'cat_drinks',
  name: 'Ayran',
  description: '',
  basePrice: 25.0,
  imageKey: 'ayran',
);

void main() {
  late FakeClock clock;
  late InMemoryPosOrderRepository repository;
  late ProviderContainer container;

  ProviderContainer buildContainer() {
    clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
    repository = InMemoryPosOrderRepository();
    return ProviderContainer(
      overrides: [
        clockProvider.overrideWithValue(clock),
        posOrderRepositoryProvider.overrideWithValue(repository),
      ],
    );
  }

  void startSession(ProviderContainer c) {
    c.read(posOrderSessionProvider.notifier).startSession(
          sessionId: 'session-1',
          branchId: 'branch-1',
          openedByStaffId: 'staff-1',
          channel: OrderChannel.dineInStaff,
        );
  }

  setUp(() {
    container = buildContainer();
  });

  tearDown(() {
    container.dispose();
  });

  group('PosOrderSessionController — idle/start', () {
    test('build() starts idle with no session', () {
      final state = container.read(posOrderSessionProvider);

      expect(state.status, PosOrderSessionStatus.idle);
      expect(state.session, isNull);
    });

    test('startSession moves to editing and persists a draft', () {
      startSession(container);
      final state = container.read(posOrderSessionProvider);

      expect(state.status, PosOrderSessionStatus.editing);
      expect(state.session, isNotNull);
      expect(state.session!.sessionId, 'session-1');
      expect(repository.draftIds, contains('session-1'));
    });
  });

  group('PosOrderSessionController — editing mutations', () {
    test('addProduct is a no-op when there is no active session', () async {
      await container
          .read(posOrderSessionProvider.notifier)
          .addProduct(product: _simpleProduct);

      expect(container.read(posOrderSessionProvider).status,
          PosOrderSessionStatus.idle);
    });

    test('addProduct appends a line and stays in editing', () async {
      startSession(container);

      await container
          .read(posOrderSessionProvider.notifier)
          .addProduct(product: _simpleProduct);

      final state = container.read(posOrderSessionProvider);
      expect(state.status, PosOrderSessionStatus.editing);
      expect(state.session!.lines, hasLength(1));
    });

    test(
        'a rejected mutation surfaces a failure without losing the session field on the next successful mutation',
        () async {
      startSession(container);
      final notifier = container.read(posOrderSessionProvider.notifier);

      // quantity 0 is rejected by AddProductToPosOrder (NonPositiveQuantityViolation).
      await notifier.addProduct(product: _simpleProduct, quantity: 0);
      final afterFailure = container.read(posOrderSessionProvider);
      expect(afterFailure.status, PosOrderSessionStatus.failure);
      expect(afterFailure.error, isA<PosValidationError>());

      await notifier.addProduct(product: _simpleProduct);
      final afterRecovery = container.read(posOrderSessionProvider);
      expect(afterRecovery.status, PosOrderSessionStatus.editing);
      expect(afterRecovery.session!.lines, hasLength(1));
    });
  });

  group('PosOrderSessionController — submit', () {
    test(
        'submit with no active session sets a failure state with PosNoActiveSessionError',
        () async {
      await container
          .read(posOrderSessionProvider.notifier)
          .submit(restaurantId: 'restaurant-abakus');

      final state = container.read(posOrderSessionProvider);
      expect(state.status, PosOrderSessionStatus.failure);
      expect(state.error, isA<PosNoActiveSessionError>());
      expect(state.session, isNull);
    });

    test(
        'submit with an empty session (no lines) fails and preserves the session',
        () async {
      startSession(container);

      await container
          .read(posOrderSessionProvider.notifier)
          .submit(restaurantId: 'restaurant-abakus');

      final state = container.read(posOrderSessionProvider);
      expect(state.status, PosOrderSessionStatus.failure);
      expect(state.error, isA<PosSubmissionRejectedError>());
      expect(state.session, isNotNull);
    });

    test(
        'a successful submission clears the session, keeps submittedOrder, and deletes the draft',
        () async {
      startSession(container);
      final notifier = container.read(posOrderSessionProvider.notifier);
      await notifier.addProduct(product: _simpleProduct);

      await notifier.submit(restaurantId: 'restaurant-abakus');

      final state = container.read(posOrderSessionProvider);
      expect(state.status, PosOrderSessionStatus.submitted);
      expect(state.submittedOrder, isNotNull);
      expect(state.session, isNull);
      expect(repository.draftIds, isNot(contains('session-1')));
    });

    test(
        'a second concurrent submit call is ignored while the first is in flight',
        () async {
      startSession(container);
      final notifier = container.read(posOrderSessionProvider.notifier);
      await notifier.addProduct(product: _simpleProduct);

      final first = notifier.submit(restaurantId: 'restaurant-abakus');
      final second = notifier.submit(restaurantId: 'restaurant-abakus');
      await first;
      await second;

      expect(repository.submittedOrders, hasLength(1));
    });

    test(
        'a failed submission (repository error) preserves the session and permits retry',
        () async {
      startSession(container);
      final notifier = container.read(posOrderSessionProvider.notifier);
      await notifier.addProduct(product: _simpleProduct);
      repository.failOnSubmitOrder = Exception('backend unavailable');

      await notifier.submit(restaurantId: 'restaurant-abakus');

      final failed = container.read(posOrderSessionProvider);
      expect(failed.status, PosOrderSessionStatus.failure);
      expect(failed.error, isA<PosRepositoryError>());
      expect(failed.session, isNotNull);
      expect(failed.session!.lines, hasLength(1));

      // Retry: the same session is still there to submit again.
      await notifier.submit(restaurantId: 'restaurant-abakus');
      final recovered = container.read(posOrderSessionProvider);
      expect(recovered.status, PosOrderSessionStatus.submitted);
      expect(recovered.submittedOrder, isNotNull);
    });
  });

  group('PosOrderSessionController — id-based line operations', () {
    test('updateLine changes the quantity of the line with the given draft id',
        () async {
      startSession(container);
      final notifier = container.read(posOrderSessionProvider.notifier);
      await notifier.addProduct(product: _simpleProduct);
      final draftId =
          container.read(posOrderSessionProvider).session!.lines.single.id;

      await notifier.updateLine(orderLineDraftId: draftId, quantity: 3);

      final state = container.read(posOrderSessionProvider);
      expect(state.status, PosOrderSessionStatus.editing);
      expect(state.session!.lines.single.item.quantity, 3);
    });

    test('removeLine removes the line with the given draft id', () async {
      startSession(container);
      final notifier = container.read(posOrderSessionProvider.notifier);
      await notifier.addProduct(product: _simpleProduct);
      final draftId =
          container.read(posOrderSessionProvider).session!.lines.single.id;

      await notifier.removeLine(draftId);

      final state = container.read(posOrderSessionProvider);
      expect(state.session!.lines, isEmpty);
    });

    test('an unknown draft id surfaces a validation failure, session preserved',
        () async {
      startSession(container);
      final notifier = container.read(posOrderSessionProvider.notifier);
      await notifier.addProduct(product: _simpleProduct);

      await notifier.removeLine('nonexistent-draft-id');

      final state = container.read(posOrderSessionProvider);
      expect(state.status, PosOrderSessionStatus.failure);
      expect(state.error, isA<PosValidationError>());
      expect(state.session!.lines, hasLength(1));
    });
  });

  group('PosOrderSessionController — setDiscount', () {
    test('sets a line-scoped discount targeting a specific line', () async {
      startSession(container);
      final notifier = container.read(posOrderSessionProvider.notifier);
      await notifier.addProduct(product: _simpleProduct);
      final draftId =
          container.read(posOrderSessionProvider).session!.lines.single.id;

      await notifier.setDiscount(
        scope: DiscountScope.line,
        targetOrderLineId: draftId,
        preset: DiscountPresetSeedData.tenPercent,
        appliedByStaffId: 'staff-1',
      );

      final state = container.read(posOrderSessionProvider);
      expect(state.status, PosOrderSessionStatus.editing);
      expect(state.session!.discounts, hasLength(1));
      expect(state.session!.discounts.single.targetOrderLineId, draftId);
    });

    test('setting a new discount on the same line replaces the previous one',
        () async {
      startSession(container);
      final notifier = container.read(posOrderSessionProvider.notifier);
      await notifier.addProduct(product: _simpleProduct);
      final draftId =
          container.read(posOrderSessionProvider).session!.lines.single.id;

      await notifier.setDiscount(
        scope: DiscountScope.line,
        targetOrderLineId: draftId,
        preset: DiscountPresetSeedData.fivePercent,
        appliedByStaffId: 'staff-1',
      );
      await notifier.setDiscount(
        scope: DiscountScope.line,
        targetOrderLineId: draftId,
        preset: DiscountPresetSeedData.twentyPercent,
        appliedByStaffId: 'staff-1',
      );

      final state = container.read(posOrderSessionProvider);
      expect(state.session!.discounts, hasLength(1));
      expect(state.session!.discounts.single.percentageBasisPoints, 2000);
    });

    test('setDiscount with preset: null clears the active discount', () async {
      startSession(container);
      final notifier = container.read(posOrderSessionProvider.notifier);
      await notifier.addProduct(product: _simpleProduct);
      final draftId =
          container.read(posOrderSessionProvider).session!.lines.single.id;
      await notifier.setDiscount(
        scope: DiscountScope.line,
        targetOrderLineId: draftId,
        preset: DiscountPresetSeedData.tenPercent,
        appliedByStaffId: 'staff-1',
      );

      await notifier.setDiscount(
        scope: DiscountScope.line,
        targetOrderLineId: draftId,
        preset: null,
        appliedByStaffId: 'staff-1',
      );

      final state = container.read(posOrderSessionProvider);
      expect(state.session!.discounts, isEmpty);
    });
  });

  group('PosOrderSessionController — cancelSession', () {
    test('discards the draft and returns to idle', () async {
      startSession(container);
      final notifier = container.read(posOrderSessionProvider.notifier);
      await notifier.addProduct(product: _simpleProduct);
      expect(repository.draftIds, contains('session-1'));

      await notifier.cancelSession();

      final state = container.read(posOrderSessionProvider);
      expect(state.status, PosOrderSessionStatus.idle);
      expect(state.session, isNull);
      expect(repository.draftIds, isNot(contains('session-1')));
    });
  });
}
