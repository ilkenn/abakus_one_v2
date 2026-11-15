import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

/// A file the courier picked: its bytes, content type and name.
typedef CourierPickedDocument = ({
  Uint8List bytes,
  String contentType,
  String name,
});

/// ADR-085 stage 6A — picking an invoice file (PDF, or a photo of a paper
/// invoice) in the courier app, and opening a PDF in the panel. Behind an
/// interface so widget tests never touch the platform.
abstract interface class CourierDocumentService {
  /// A PDF from the device's files, or `null` when cancelled.
  Future<CourierPickedDocument?> pickPdf();

  /// A photo from the camera or the gallery, or `null` when cancelled.
  Future<CourierPickedDocument?> pickPhoto({required bool fromCamera});

  /// Opens a PDF with the device's viewer; `false` when it cannot.
  Future<bool> openPdf(Uint8List bytes, {required String name});
}

class DeviceCourierDocumentService implements CourierDocumentService {
  const DeviceCourierDocumentService();

  @override
  Future<CourierPickedDocument?> pickPdf() async {
    final file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(
        label: 'PDF',
        extensions: ['pdf'],
        mimeTypes: ['application/pdf'],
        uniformTypeIdentifiers: ['com.adobe.pdf'],
      ),
    ]);
    if (file == null) return null;
    return (
      bytes: await file.readAsBytes(),
      contentType: 'application/pdf',
      name: file.name,
    );
  }

  @override
  Future<CourierPickedDocument?> pickPhoto({required bool fromCamera}) async {
    final photo = await ImagePicker().pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 75,
      maxWidth: 2000,
    );
    if (photo == null) return null;
    final name = photo.name.toLowerCase();
    return (
      bytes: await photo.readAsBytes(),
      contentType: name.endsWith('.png') ? 'image/png' : 'image/jpeg',
      name: photo.name,
    );
  }

  @override
  Future<bool> openPdf(Uint8List bytes, {required String name}) async {
    try {
      final file = File('${Directory.systemTemp.path}${Platform.pathSeparator}'
          '$name');
      await file.writeAsBytes(bytes, flush: true);
      return await launchUrl(Uri.file(file.path));
    } catch (_) {
      return false;
    }
  }
}
