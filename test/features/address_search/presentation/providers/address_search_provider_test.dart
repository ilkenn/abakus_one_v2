import 'package:abakus_one_v2/features/address_search/domain/models/address_suggestion.dart';
import 'package:abakus_one_v2/features/address_search/domain/models/resolved_address.dart';
import 'package:abakus_one_v2/features/address_search/domain/services/address_search_provider.dart';
import 'package:abakus_one_v2/features/address_search/presentation/providers/address_search_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAddressSearchProvider implements AddressSearchProvider {
  _FakeAddressSearchProvider();

  final List<String> autocompleteCalls = [];
  Object? errorToThrow;

  @override
  Future<List<AddressSuggestion>> autocomplete({
    required String input,
    required String sessionToken,
  }) async {
    autocompleteCalls.add(input);
    if (errorToThrow != null) throw errorToThrow!;
    return [
      AddressSuggestion(providerPlaceId: 'place-for-$input', text: input)
    ];
  }

  @override
  Future<ResolvedAddress> resolvePlace({
    required String placeId,
    required String sessionToken,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<ResolvedAddress> reverseGeocode({
    required double latitude,
    required double longitude,
  }) async {
    throw UnimplementedError();
  }
}

void main() {
  late _FakeAddressSearchProvider fake;
  late ProviderContainer container;

  setUp(() {
    fake = _FakeAddressSearchProvider();
    container = ProviderContainer(
      overrides: [addressSearchProviderProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
  });

  test(
      'an empty query clears suggestions and never calls the provider '
      '(req 12 debounce/cost control)', () async {
    container.listen(addressSearchProvider, (_, __) {});
    container.read(addressSearchProvider.notifier).onQueryChanged('');
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(fake.autocompleteCalls, isEmpty);
    expect(container.read(addressSearchProvider).suggestions, isEmpty);
  });

  test(
      'rapid keystrokes are debounced — only the final query triggers a '
      'request (req 12)', () async {
    container.listen(addressSearchProvider, (_, __) {});
    final notifier = container.read(addressSearchProvider.notifier);
    notifier.onQueryChanged('B');
    notifier.onQueryChanged('Be');
    notifier.onQueryChanged('Beş');
    notifier.onQueryChanged('Beşiktaş');

    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(fake.autocompleteCalls, ['Beşiktaş']);
  });

  test('a successful search populates suggestions', () async {
    container.listen(addressSearchProvider, (_, __) {});
    container.read(addressSearchProvider.notifier).onQueryChanged('Beşiktaş');
    await Future<void>.delayed(const Duration(milliseconds: 500));

    final state = container.read(addressSearchProvider);
    expect(state.suggestions, hasLength(1));
    expect(state.isSearching, isFalse);
  });

  test('a failed search surfaces a safe error, never throws uncaught',
      () async {
    fake.errorToThrow = Exception('network down');
    container.listen(addressSearchProvider, (_, __) {});
    container.read(addressSearchProvider.notifier).onQueryChanged('Beşiktaş');
    await Future<void>.delayed(const Duration(milliseconds: 500));

    final state = container.read(addressSearchProvider);
    expect(state.error, isNotNull);
    expect(state.isSearching, isFalse);
  });

  test('retireSession() rotates the session token', () {
    container.listen(addressSearchProvider, (_, __) {});
    final before = container.read(addressSearchProvider).sessionToken;
    container.read(addressSearchProvider.notifier).retireSession();
    final after = container.read(addressSearchProvider).sessionToken;

    expect(after, isNot(before));
  });

  test(
      'every autocomplete call within one session reuses the same '
      'sessionToken until retireSession() is called', () async {
    container.listen(addressSearchProvider, (_, __) {});
    final tokenBefore = container.read(addressSearchProvider).sessionToken;
    container.read(addressSearchProvider.notifier).onQueryChanged('Şişli');
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(container.read(addressSearchProvider).sessionToken, tokenBefore);
  });
}
