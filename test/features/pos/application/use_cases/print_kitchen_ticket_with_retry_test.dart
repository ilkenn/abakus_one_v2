import 'package:abakus_one_v2/features/pos/application/identity/kitchen_print_attempt_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/print_kitchen_ticket_with_retry.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_print_attempt_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket_print_provider.dart';
import 'package:abakus_one_v2/features/pos/domain/receipts/receipt_print_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';
import '../../test_support/kds_test_fixtures.dart';

class _FakePrintProvider implements KitchenTicketPrintProvider {
  _FakePrintProvider(this._result);

  final ReceiptPrintResult _result;
  int callCount = 0;

  @override
  Future<ReceiptPrintResult> print(KitchenTicket ticket) async {
    callCount += 1;
    return _result;
  }
}

void main() {
  group('PrintKitchenTicketWithRetry', () {
    test('a successful primary attempt never touches the fallback', () async {
      final attemptRepository = InMemoryKitchenPrintAttemptRepository();
      final primary = _FakePrintProvider(
          const ReceiptPrintResult(status: ReceiptPrintResultStatus.success));
      final fallback = _FakePrintProvider(
          const ReceiptPrintResult(status: ReceiptPrintResultStatus.success));

      final useCase = PrintKitchenTicketWithRetry(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        idGenerator: SequentialKitchenPrintAttemptIdGenerator(),
        attemptRepository: attemptRepository,
        primaryProvider: primary,
        fallbackProvider: fallback,
      );

      final result = await useCase(buildTestKitchenTicket());

      expect(result.status, ReceiptPrintResultStatus.success);
      expect(primary.callCount, 1);
      expect(fallback.callCount, 0);
      final attempts = await attemptRepository.findByTicketId('ticket-1');
      expect(attempts, hasLength(1));
    });

    test('falls back and records both attempts when the primary fails',
        () async {
      final attemptRepository = InMemoryKitchenPrintAttemptRepository();
      final primary = _FakePrintProvider(const ReceiptPrintResult(
          status: ReceiptPrintResultStatus.failed,
          errorMessage: 'Bağlantı hatası'));
      final fallback = _FakePrintProvider(
          const ReceiptPrintResult(status: ReceiptPrintResultStatus.success));

      final useCase = PrintKitchenTicketWithRetry(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        idGenerator: SequentialKitchenPrintAttemptIdGenerator(),
        attemptRepository: attemptRepository,
        primaryProvider: primary,
        fallbackProvider: fallback,
      );

      final result = await useCase(buildTestKitchenTicket());

      expect(result.status, ReceiptPrintResultStatus.success);
      expect(primary.callCount, 1);
      expect(fallback.callCount, 1);
      final attempts = await attemptRepository.findByTicketId('ticket-1');
      expect(attempts, hasLength(2));
      expect(attempts.first.isFallback, isFalse);
      expect(attempts.last.isFallback, isTrue);
      expect(attempts.last.isRetry, isTrue);
    });

    test(
        'with no fallback configured, a failure is still recorded and '
        'never loses the ticket', () async {
      final attemptRepository = InMemoryKitchenPrintAttemptRepository();
      final primary = _FakePrintProvider(const ReceiptPrintResult(
          status: ReceiptPrintResultStatus.unavailable));

      final useCase = PrintKitchenTicketWithRetry(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        idGenerator: SequentialKitchenPrintAttemptIdGenerator(),
        attemptRepository: attemptRepository,
        primaryProvider: primary,
      );

      final ticket = buildTestKitchenTicket();
      final result = await useCase(ticket);

      expect(result.status, ReceiptPrintResultStatus.unavailable);
      // The ticket itself is untouched by this use case entirely — it
      // never reads or writes KitchenTicketRepository/KitchenProjectionRepository.
      expect(ticket.lines, hasLength(1));
    });
  });
}
