import '../domain/models/address_suggestion.dart';
import '../domain/models/resolved_address.dart';

/// Pure parsing of the `searchAddressAutocomplete` callable's JSON
/// response into this app's provider-neutral [AddressSuggestion] model —
/// Faz P.2. Extracted from `GooglePlacesAddressSearchProvider` so it's
/// unit-testable without the `cloud_functions` SDK, which is unavailable
/// under `flutter test` (mirrors `SubmitTakeawayOrderGateway`'s own
/// established reasoning for why its network-calling classes aren't
/// tested directly either — only their pure parsing logic, where it
/// exists, is).
List<AddressSuggestion> parseAutocompleteSuggestions(List<dynamic> raw) {
  return [
    for (final entry in raw.cast<Map<dynamic, dynamic>>())
      AddressSuggestion(
        providerPlaceId: entry['placeId'] as String,
        text: entry['text'] as String,
      ),
  ];
}

ResolvedAddress parseResolvedAddress(Map<String, dynamic> data) {
  final resolved = data['resolved'] as Map<dynamic, dynamic>;
  return ResolvedAddress(
    providerPlaceId: resolved['providerPlaceId'] as String,
    formattedAddress: resolved['formattedAddress'] as String?,
    provinceName: resolved['provinceName'] as String?,
    districtName: resolved['districtName'] as String?,
    neighborhoodName: resolved['neighborhoodName'] as String?,
    routeName: resolved['routeName'] as String?,
    streetNumber: resolved['streetNumber'] as String?,
    latitude: (resolved['latitude'] as num?)?.toDouble(),
    longitude: (resolved['longitude'] as num?)?.toDouble(),
    isSufficientlyResolved: data['sufficientlyResolved'] as bool,
  );
}
