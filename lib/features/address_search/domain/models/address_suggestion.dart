/// One autocomplete suggestion — Faz P.2. Provider-neutral: carries no
/// Google Places SDK/response type. [providerPlaceId] is opaque to this
/// app (never parsed, only round-tripped back to
/// `AddressSearchProvider.resolvePlace`).
class AddressSuggestion {
  const AddressSuggestion({
    required this.providerPlaceId,
    required this.text,
  });

  final String providerPlaceId;

  /// The provider's own human-readable suggestion text (e.g. "Balmumcu,
  /// Barbaros Bulvarı No:74, Beşiktaş/İstanbul, Türkiye") — shown as-is in
  /// the picker; never parsed for address components (that only happens
  /// server-side, via `resolvePlace`/`saveDeliveryAddress`).
  final String text;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AddressSuggestion &&
          other.providerPlaceId == providerPlaceId &&
          other.text == text);

  @override
  int get hashCode => Object.hash(providerPlaceId, text);
}
