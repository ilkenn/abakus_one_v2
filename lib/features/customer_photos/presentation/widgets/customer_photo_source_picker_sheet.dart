import 'package:flutter/material.dart';

import '../../data/customer_photo_picker.dart';

/// CR.1.2 — the "Galeriden Seç / Kameradan Çek" bottom sheet, extracted
/// once a second caller (`Step2PhotoStep`, alongside the existing
/// `CustomerPhotoManagementScreen`) needed the exact same source choice —
/// this repo's own "2nd consumer promotes to a shared location"
/// convention, applied here to a small UI helper rather than a whole
/// file. Returns `null` if the sheet was dismissed without a choice.
Future<CustomerPhotoPickSource?> showCustomerPhotoSourcePicker(
  BuildContext context,
) {
  return showModalBottomSheet<CustomerPhotoPickSource>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Galeriden Seç'),
            onTap: () => Navigator.pop(
              sheetContext,
              CustomerPhotoPickSource.gallery,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Kameradan Çek'),
            onTap: () => Navigator.pop(
              sheetContext,
              CustomerPhotoPickSource.camera,
            ),
          ),
        ],
      ),
    ),
  );
}
