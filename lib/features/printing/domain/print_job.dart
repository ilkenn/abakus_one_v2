/// AP-5 Sprint 1 — printer engine skeleton only. No `PrinterAdapter`
/// transport exists yet (gated on the target printer hardware vendor's own
/// ESC/POS reference manual, `docs/kds_printer_stock_architecture.md` §24,
/// same class of external dependency as AP-4's PAX/GMP-3 fiscal boundary)
/// — this models the print-job/queue shape only, mirroring
/// `KitchenPrintAttempt`'s existing real shape, not a working printer.
enum PrintJobStatus { pending, printing, success, failed }

/// One request to print a kitchen ticket or receipt at a specific station's
/// printer — the durable queue entry `RequestPrintJob`/`RecordPrintOutcome`
/// (a later sprint) will operate on. A reprint/duplicate is always a
/// **new**, distinct [PrintJob] — never mutated in place to look like the
/// original (mirrors `KitchenPrintAttempt.isRetry`'s existing distinction).
class PrintJob {
  const PrintJob({
    required this.printJobId,
    required this.orderId,
    required this.stationId,
    this.retryCount = 0,
    required this.status,
    this.backupPrinterId,
  });

  final String printJobId;
  final String orderId;
  final String stationId;

  /// How many retry attempts this job has already made — `0` for the
  /// first attempt.
  final int retryCount;

  final PrintJobStatus status;

  /// The fallback printer this job routes to if the primary printer for
  /// [stationId] is unreachable, if one is configured for the branch —
  /// `null` when no fallback exists.
  final String? backupPrinterId;

  PrintJob copyWith({
    int? retryCount,
    PrintJobStatus? status,
    String? backupPrinterId,
  }) {
    return PrintJob(
      printJobId: printJobId,
      orderId: orderId,
      stationId: stationId,
      retryCount: retryCount ?? this.retryCount,
      status: status ?? this.status,
      backupPrinterId: backupPrinterId ?? this.backupPrinterId,
    );
  }

  /// Deterministic per (order, station, attempt generation) — the same
  /// "duplicate call, same key, no duplicate record" idempotency shape
  /// `RecordStockMovement`/`KitchenWorkItem.idempotencyKey` already
  /// establish, so a duplicate enqueue for the same print generation never
  /// creates a second queue entry.
  static String derivePrintJobId({
    required String orderId,
    required String stationId,
    required int attemptGeneration,
  }) {
    return 'print-$orderId-$stationId-gen$attemptGeneration';
  }
}
