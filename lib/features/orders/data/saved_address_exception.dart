/// Thrown by [SavedAddressRepository] for an expected, non-exceptional-
/// in-nature rejection — mirrors the `saveDeliveryAddress` Cloud
/// Function's own `HttpsError` codes verbatim, the same reasoning as
/// `AddressSearchException`.
class SavedAddressException implements Exception {
  final String code;
  final String message;

  const SavedAddressException(this.code, this.message);

  @override
  String toString() => 'SavedAddressException($code): $message';
}
