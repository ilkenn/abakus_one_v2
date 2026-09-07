import 'package:abakus_one_v2/features/printing/domain/print_job.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PrintJob.derivePrintJobId', () {
    test('is deterministic for the same inputs', () {
      final first = PrintJob.derivePrintJobId(
        orderId: 'order-1',
        stationId: 'hot',
        attemptGeneration: 1,
      );
      final second = PrintJob.derivePrintJobId(
        orderId: 'order-1',
        stationId: 'hot',
        attemptGeneration: 1,
      );
      expect(first, second);
    });

    test('differs when orderId differs', () {
      final a = PrintJob.derivePrintJobId(
        orderId: 'order-1',
        stationId: 'hot',
        attemptGeneration: 1,
      );
      final b = PrintJob.derivePrintJobId(
        orderId: 'order-2',
        stationId: 'hot',
        attemptGeneration: 1,
      );
      expect(a, isNot(b));
    });

    test('differs when stationId differs', () {
      final a = PrintJob.derivePrintJobId(
        orderId: 'order-1',
        stationId: 'hot',
        attemptGeneration: 1,
      );
      final b = PrintJob.derivePrintJobId(
        orderId: 'order-1',
        stationId: 'cold',
        attemptGeneration: 1,
      );
      expect(a, isNot(b));
    });

    test('differs when attemptGeneration differs — a retry is a new job id',
        () {
      final a = PrintJob.derivePrintJobId(
        orderId: 'order-1',
        stationId: 'hot',
        attemptGeneration: 1,
      );
      final b = PrintJob.derivePrintJobId(
        orderId: 'order-1',
        stationId: 'hot',
        attemptGeneration: 2,
      );
      expect(a, isNot(b));
    });
  });

  group('PrintJob.copyWith', () {
    test('overrides only the specified fields, keeping identity fields fixed',
        () {
      const job = PrintJob(
        printJobId: 'print-1',
        orderId: 'order-1',
        stationId: 'hot',
        status: PrintJobStatus.pending,
      );
      final retried =
          job.copyWith(status: PrintJobStatus.failed, retryCount: 1);

      expect(retried.printJobId, 'print-1');
      expect(retried.orderId, 'order-1');
      expect(retried.stationId, 'hot');
      expect(retried.status, PrintJobStatus.failed);
      expect(retried.retryCount, 1);
    });
  });
}
