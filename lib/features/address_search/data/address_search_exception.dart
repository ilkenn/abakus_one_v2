/// Thrown by [GooglePlacesAddressSearchProvider] for an expected,
/// non-exceptional-in-nature rejection — mirrors the Cloud Function's own
/// `HttpsError` codes verbatim, the same reasoning as
/// `SubmitTakeawayOrderException`/`TableGuestSessionException`.
class AddressSearchException implements Exception {
  final String code;
  final String message;

  const AddressSearchException(this.code, this.message);

  @override
  String toString() => 'AddressSearchException($code): $message';
}
