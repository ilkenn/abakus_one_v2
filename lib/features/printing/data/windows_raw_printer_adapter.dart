import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

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
abstract interface class RawPrinterAdapter {
  Future<void> printRaw({
    required String printerName,
    required Uint8List bytes,
    required String jobName,
  });
}

/// The real implementation — `winspool.drv` (`OpenPrinter`/`StartDocPrinter`
/// with the `RAW` datatype/`WritePrinter`), reached through `package:win32`.
/// This is genuinely Windows-only: `winspool.drv` doesn't exist on any other
/// platform, and this app also builds for Android/iOS/Web, so every call
/// fails closed with [RawPrinterException] off Windows rather than crashing
/// on a missing native symbol.
class WindowsRawPrinterAdapter implements RawPrinterAdapter {
  const WindowsRawPrinterAdapter();

  @override
  Future<void> printRaw({
    required String printerName,
    required Uint8List bytes,
    required String jobName,
  }) async {
    if (!Platform.isWindows) {
      throw const RawPrinterException(
          'Doğrudan yazıcı kuyruğuna yazdırma yalnızca Windows\'ta desteklenir.');
    }
    if (bytes.isEmpty) {
      throw const RawPrinterException('Yazdırılacak fiş içeriği boş.');
    }

    final phPrinter = calloc<Pointer>();
    final printerNamePtr = printerName.toNativeUtf16();
    Pointer<Utf16>? docNamePtr;
    Pointer<Utf16>? dataTypePtr;
    Pointer<DOC_INFO_1>? docInfoPtr;
    Pointer<Uint8>? bufferPtr;
    Pointer<Uint32>? writtenPtr;
    PRINTER_HANDLE? handle;

    try {
      final opened = OpenPrinter(PCWSTR(printerNamePtr), phPrinter, nullptr);
      if (!opened.value || phPrinter.value == nullptr) {
        throw RawPrinterException(
            'Yazıcı bulunamadı: "$printerName". Windows\'ta bu adla kurulu '
            'bir yazıcı olduğundan emin olun.');
      }
      handle = PRINTER_HANDLE(phPrinter.value);

      docNamePtr = jobName.toNativeUtf16();
      dataTypePtr = 'RAW'.toNativeUtf16();
      docInfoPtr = calloc<DOC_INFO_1>();
      docInfoPtr.ref
        ..pDocName = PWSTR(docNamePtr)
        ..pOutputFile = PWSTR(nullptr)
        ..pDatatype = PWSTR(dataTypePtr);

      final jobId = StartDocPrinter(handle, 1, docInfoPtr);
      if (jobId == 0) {
        throw const RawPrinterException('Yazdırma işi başlatılamadı.');
      }
      if (!StartPagePrinter(handle)) {
        throw const RawPrinterException('Yazdırma sayfası başlatılamadı.');
      }

      bufferPtr = bytes.toNative();
      writtenPtr = calloc<Uint32>();
      final wroteOk = WritePrinter(handle, bufferPtr, bytes.length, writtenPtr);
      EndPagePrinter(handle);
      EndDocPrinter(handle);
      if (!wroteOk || writtenPtr.value != bytes.length) {
        throw const RawPrinterException(
            'Fiş yazıcıya tam olarak gönderilemedi.');
      }
    } finally {
      if (handle != null) ClosePrinter(handle);
      calloc.free(phPrinter);
      calloc.free(printerNamePtr);
      if (docNamePtr != null) calloc.free(docNamePtr);
      if (dataTypePtr != null) calloc.free(dataTypePtr);
      if (docInfoPtr != null) calloc.free(docInfoPtr);
      if (bufferPtr != null) calloc.free(bufferPtr);
      if (writtenPtr != null) calloc.free(writtenPtr);
    }
  }
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
