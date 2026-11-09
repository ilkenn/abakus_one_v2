import 'dart:typed_data';

/// Thrown for every failure path below — always carries an already-Turkish,
/// user-safe message (never a raw Win32/FFI exception surfaced to staff),
/// matching this codebase's `ErrorMapper`-boundary convention for every
/// other gateway.
class RawPrinterException implements Exception {
  const RawPrinterException(this.message);
  final String message;
  @override
  String toString() => 'RawPrinterException: $message';
}

/// Sends a raw byte stream straight to a named printer's spool queue,
/// bypassing any page-rendering/driver formatting — the transport an
/// ESC/POS till receipt needs (`EscPosReceiptEncoder`'s output is already
/// fully formatted; nothing here interprets the bytes).
///
/// Platform-neutral on purpose (2026-11-09): this file must compile on Web,
/// so it carries no `dart:ffi`/`package:win32` import. The Windows
/// implementation lives in `windows_raw_printer_adapter_ffi.dart`, selected
/// by the conditional export in `windows_raw_printer_adapter.dart`.
abstract interface class RawPrinterAdapter {
  Future<void> printRaw({
    required String printerName,
    required Uint8List bytes,
    required String jobName,
  });
}

/// Fail-closed fallback for every non-Windows target (Android/iOS/Web) —
/// mirrors every other `Unavailable*Gateway` in this codebase rather than
/// silently no-opping.
class UnavailableRawPrinterAdapter implements RawPrinterAdapter {
  const UnavailableRawPrinterAdapter();

  @override
  Future<void> printRaw({
    required String printerName,
    required Uint8List bytes,
    required String jobName,
  }) async {
    throw const RawPrinterException(
        'Fiş yazdırma bu platformda desteklenmiyor.');
  }
}
