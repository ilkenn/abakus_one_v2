import 'package:cloud_functions/cloud_functions.dart' as functions;

import '../domain/models/address_suggestion.dart';
import '../domain/models/resolved_address.dart';
import '../domain/services/address_search_provider.dart';
import 'address_search_exception.dart';
import 'google_places_response_mapping.dart';

/// Google Places API (New) implementation of [AddressSearchProvider] —
/// Faz P.2. Calls the `searchAddressAutocomplete`/`resolveAddressPlace`
/// Cloud Function callables (`functions/src/deliveryPlaces.ts`) — never
/// calls Google's API directly from the client. No Google Places SDK
/// dependency exists in `pubspec.yaml`; this class's only external
/// dependency is `cloud_functions`, already used throughout this app for
/// every other server-authoritative operation. **This is the only file in
/// this app that knows a provider named "Google" exists at all** — every
/// caller of [AddressSearchProvider] (the interface) has no idea.
class GooglePlacesAddressSearchProvider implements AddressSearchProvider {
  GooglePlacesAddressSearchProvider(
      {functions.FirebaseFunctions? functionsInstance})
      : _functions = functionsInstance ?? functions.FirebaseFunctions.instance;

  final functions.FirebaseFunctions _functions;

  @override
  Future<List<AddressSuggestion>> autocomplete({
    required String input,
    required String sessionToken,
  }) async {
    final callable = _functions.httpsCallable('searchAddressAutocomplete');
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'input': input,
        'sessionToken': sessionToken,
      });
      return parseAutocompleteSuggestions(
        result.data['suggestions'] as List,
      );
    } on functions.FirebaseFunctionsException catch (error) {
      throw AddressSearchException(
        error.code,
        error.message ?? 'Adres önerileri alınamadı.',
      );
    }
  }

  @override
  Future<ResolvedAddress> resolvePlace({
    required String placeId,
    required String sessionToken,
  }) async {
    final callable = _functions.httpsCallable('resolveAddressPlace');
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'placeId': placeId,
        'sessionToken': sessionToken,
      });
      return parseResolvedAddress(result.data);
    } on functions.FirebaseFunctionsException catch (error) {
      throw AddressSearchException(
        error.code,
        error.message ?? 'Adres çözümlenemedi.',
      );
    }
  }

  @override
  Future<ResolvedAddress> reverseGeocode({
    required double latitude,
    required double longitude,
  }) async {
    final callable = _functions.httpsCallable('reverseGeocodeAddressPoint');
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'latitude': latitude,
        'longitude': longitude,
      });
      return parseResolvedAddress(result.data);
    } on functions.FirebaseFunctionsException catch (error) {
      throw AddressSearchException(
        error.code,
        error.message ?? 'Konum çözümlenemedi.',
      );
    }
  }
}
