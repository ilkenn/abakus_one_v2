import 'dart:typed_data';

import 'raw_printer_adapter.dart';

/// Web stand-in for the FFI-backed `WindowsRawPrinterAdapter` (2026-11-09).
/// `dart:ffi`/`package:win32` don't exist on Web, so the conditional export
/// in `windows_raw_printer_adapter.dart` picks this file there. Same class
/// name, so no importer changes; every call fails closed, exactly like the
/// real adapter does off Windows.
class WindowsRawPrinterAdapter implements RawPrinterAdapter {
  const WindowsRawPrinterAdapter();

  @override
  Future<void> printRaw({
    required String printerName,
    required Uint8List bytes,
    required String jobName,
  }) async {
    throw const RawPrinterException(
        'Doğrudan yazıcı kuyruğuna yazdırma yalnızca Windows\'ta desteklenir.');
  }
}
