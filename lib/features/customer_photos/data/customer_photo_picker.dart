import 'dart:typed_data';

import 'package:image_picker/image_picker.dart' as picker;

/// Where the customer chooses their photo from — deliberately not
/// re-exporting `image_picker`'s own `ImageSource` so nothing outside this
/// file depends on the vendor package directly (mirrors `FirebaseAuthClient`'s
/// "no vendor type crosses this boundary" discipline).
enum CustomerPhotoPickSource { gallery, camera }

/// The vendor-free result of a successful pick — already-read bytes
/// (works identically on Web/Android/iOS; `XFile.readAsBytes()` is the
/// one cross-platform API `cross_file` guarantees, unlike `File(path)`
/// which does not exist as a concept on Web), the original file name
/// (for extension-based content-type fallback — see
/// `resolveCustomerPhotoContentType`), and whatever `mimeType` the
/// platform reported (`null` on Android/iOS, real on Web).
class PickedCustomerPhoto {
  const PickedCustomerPhoto({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final String? mimeType;
}

/// Thin, mockable interface over `image_picker`'s `ImagePicker` — the real
/// plugin is unavailable under `flutter test` (platform-channel-backed),
/// mirrors `FirebaseAuthClient`'s exact "wrap the vendor SDK, never call
/// it directly from application code" reasoning.
abstract interface class CustomerPhotoPicker {
  /// `null` means the user cancelled the picker — never an error.
  Future<PickedCustomerPhoto?> pickImage({
    required CustomerPhotoPickSource source,
  });
}

class ImagePickerCustomerPhotoPicker implements CustomerPhotoPicker {
  const ImagePickerCustomerPhotoPicker({picker.ImagePicker? imagePicker})
      : _imagePicker = imagePicker;

  final picker.ImagePicker? _imagePicker;
  picker.ImagePicker get _picker => _imagePicker ?? picker.ImagePicker();

  @override
  Future<PickedCustomerPhoto?> pickImage({
    required CustomerPhotoPickSource source,
  }) async {
    final xFile = await _picker.pickImage(
      source: source == CustomerPhotoPickSource.camera
          ? picker.ImageSource.camera
          : picker.ImageSource.gallery,
      // Re-encodes to a reasonable quality where the platform supports it
      // (Web ignores this) — keeps typical phone-camera photos well under
      // the 5 MB Storage limit without a separate compression pipeline.
      imageQuality: 85,
    );
    if (xFile == null) return null;

    final bytes = await xFile.readAsBytes();
    return PickedCustomerPhoto(
      bytes: bytes,
      fileName: xFile.name,
      mimeType: xFile.mimeType,
    );
  }
}
