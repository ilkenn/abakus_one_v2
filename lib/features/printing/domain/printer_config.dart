/// The transport a [PrinterConfig] connects through — abstracted behind
/// one interface once a real `PrinterAdapter` exists (AP-5 architecture
/// doc §14, mirrors `PaymentProviderAdapter`'s pattern). No transport is
/// implemented this sprint — this enum only names the shape a future
/// adapter will branch on.
enum PrinterTransport { network, usb, bluetooth }

/// One printer registered at a branch for a specific kitchen station —
/// the doc shape backing the `printerConfigs` collection
/// (`firestore.rules`). Printer device trust itself reuses the existing
/// `TrustedDeviceRegistration` mechanism with a `PRINTER_CONTROLLER`
/// capability (architecture doc §14) rather than a parallel device model;
/// this class is the printer-specific configuration layered on top of that
/// trust, not a replacement for it.
class PrinterConfig {
  const PrinterConfig({
    required this.printerId,
    required this.branchId,
    required this.stationId,
    required this.transport,
    this.isBackup = false,
  });

  final String printerId;
  final String branchId;
  final String stationId;
  final PrinterTransport transport;

  /// `true` if this printer is the configured fallback for [stationId],
  /// never the primary — a branch may configure at most one fallback per
  /// station (enforced by whichever use case writes this, not this class).
  final bool isBackup;
}
