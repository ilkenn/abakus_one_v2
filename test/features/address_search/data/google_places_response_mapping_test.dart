import 'package:abakus_one_v2/features/address_search/data/google_places_response_mapping.dart';
import 'package:flutter_test/flutter_test.dart';

/// Proves the Dart-side response mapping (req 1: "autocomplete adapter
/// maps Google response to provider-neutral model") against fixture
/// shapes matching the real `searchAddressAutocomplete`/
/// `resolveAddressPlace` callable responses (`functions/src/
/// deliveryPlaces.ts`) — themselves built from real coverage-spike
/// evidence (`docs/decisions.md` Faz P.2).
void main() {
  group('parseAutocompleteSuggestions', () {
    test(
        'maps each suggestion to a provider-neutral AddressSuggestion '
        '(req 1)', () {
      final raw = [
        {
          'placeId': 'ChIJ4ZezpaO3yhQRQP4fWxuhun4',
          'text':
              'Balmumcu, Barbaros Bulvarı No:74, Beşiktaş/İstanbul, Türkiye',
        },
        {'placeId': 'place-2', 'text': 'Another suggestion'},
      ];

      final result = parseAutocompleteSuggestions(raw);

      expect(result, hasLength(2));
      expect(result[0].providerPlaceId, 'ChIJ4ZezpaO3yhQRQP4fWxuhun4');
      expect(result[0].text,
          'Balmumcu, Barbaros Bulvarı No:74, Beşiktaş/İstanbul, Türkiye');
      expect(result[1].providerPlaceId, 'place-2');
    });

    test('an empty suggestions list maps to an empty list', () {
      expect(parseAutocompleteSuggestions([]), isEmpty);
    });
  });

  group('parseResolvedAddress', () {
    test(
        'maps a fully resolved place: district/neighborhood/street/'
        'building/coordinates (req 4-8)', () {
      final data = {
        'resolved': {
          'providerPlaceId': 'ChIJ4ZezpaO3yhQRQP4fWxuhun4',
          'formattedAddress':
              'Balmumcu, Barbaros Blv. No:74, 34349 Beşiktaş/İstanbul, Türkiye',
          'provinceName': 'İstanbul',
          'districtName': 'Beşiktaş',
          'neighborhoodName': 'Balmumcu',
          'routeName': 'Barbaros Bulvarı',
          'streetNumber': '74',
          'latitude': 41.0449616,
          'longitude': 29.0076831,
        },
        'sufficientlyResolved': true,
      };

      final result = parseResolvedAddress(data);

      expect(result.providerPlaceId, 'ChIJ4ZezpaO3yhQRQP4fWxuhun4');
      expect(result.provinceName, 'İstanbul');
      expect(result.districtName, 'Beşiktaş');
      expect(result.neighborhoodName, 'Balmumcu');
      expect(result.routeName, 'Barbaros Bulvarı');
      expect(result.streetNumber, '74');
      expect(result.latitude, 41.0449616);
      expect(result.longitude, 29.0076831);
      expect(result.isSufficientlyResolved, isTrue);
    });

    test(
        'a mahalle-only resolution (no route/streetNumber) maps those as '
        'null, not fabricated (req 6, 7)', () {
      final data = {
        'resolved': {
          'providerPlaceId': 'place-kagithane',
          'formattedAddress': 'Ortabayır, 34413 Kağıthane/İstanbul, Türkiye',
          'provinceName': 'İstanbul',
          'districtName': 'Kağıthane',
          'neighborhoodName': 'Ortabayır',
          'routeName': null,
          'streetNumber': null,
          'latitude': 41.078883,
          'longitude': 29.003801,
        },
        'sufficientlyResolved': true,
      };

      final result = parseResolvedAddress(data);

      expect(result.routeName, isNull);
      expect(result.streetNumber, isNull);
      expect(result.isSufficientlyResolved, isTrue);
    });

    test('a place missing district maps sufficientlyResolved=false (req 5)',
        () {
      final data = {
        'resolved': {
          'providerPlaceId': 'place-maslak',
          'formattedAddress': 'Esentepe, Büyükdere Cd., İstanbul, Türkiye',
          'provinceName': 'İstanbul',
          'districtName': null,
          'neighborhoodName': 'Esentepe',
          'routeName': 'Büyükdere Caddesi',
          'streetNumber': null,
          'latitude': 41.0777007,
          'longitude': 29.0133881,
        },
        'sufficientlyResolved': false,
      };

      final result = parseResolvedAddress(data);

      expect(result.districtName, isNull);
      expect(result.isSufficientlyResolved, isFalse);
    });
  });
}
