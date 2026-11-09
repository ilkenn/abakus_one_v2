/// Entry point for raw (ESC/POS) printing — every importer keeps using this
/// path. 2026-11-09: split so the Web build compiles. The platform-neutral
/// types come from `raw_printer_adapter.dart`; `WindowsRawPrinterAdapter`
/// is the real `winspool.drv` implementation wherever `dart:ffi` exists,
/// and a fail-closed stub on Web.
library;

export 'raw_printer_adapter.dart';
export 'windows_raw_printer_adapter_stub.dart'
    if (dart.library.ffi) 'windows_raw_printer_adapter_ffi.dart';
