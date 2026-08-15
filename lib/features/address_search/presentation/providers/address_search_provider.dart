import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/address_location_gateway.dart';
import '../../data/google_places_address_search_provider.dart';
import '../../domain/models/address_suggestion.dart';
import '../../domain/services/address_search_provider.dart';

final addressSearchProviderProvider = Provider<AddressSearchProvider>((ref) {
  return GooglePlacesAddressSearchProvider();
});

final addressLocationGatewayProvider = Provider<AddressLocationGateway>((ref) {
  return const GeolocatorAddressLocationGateway();
});

class AddressSearchState {
  const AddressSearchState({
    this.query = '',
    this.suggestions = const [],
    this.isSearching = false,
    this.error,
    required this.sessionToken,
  });

  final String query;
  final List<AddressSuggestion> suggestions;
  final bool isSearching;
  final String? error;

  /// Faz P.2 §12 — one session token per search sequence, reused across
  /// every keystroke's autocomplete call, retired once a suggestion is
  /// resolved (a fresh one is generated for the next search).
  final String sessionToken;

  AddressSearchState copyWith({
    String? query,
    List<AddressSuggestion>? suggestions,
    bool? isSearching,
    String? error,
    bool clearError = false,
    String? sessionToken,
  }) {
    return AddressSearchState(
      query: query ?? this.query,
      suggestions: suggestions ?? this.suggestions,
      isSearching: isSearching ?? this.isSearching,
      error: clearError ? null : (error ?? this.error),
      sessionToken: sessionToken ?? this.sessionToken,
    );
  }
}

/// Debounced (Faz P.2 §12 — "do not send an API request for every
/// meaningless single-character change") autocomplete search state.
/// [AutoDispose] so a search session's state/timer is torn down once the
/// customer navigates away, never leaking a pending debounce timer.
class AddressSearchNotifier extends AutoDisposeNotifier<AddressSearchState> {
  static const _debounce = Duration(milliseconds: 400);
  Timer? _debounceTimer;
  int _requestGeneration = 0;

  @override
  AddressSearchState build() {
    ref.onDispose(() => _debounceTimer?.cancel());
    return AddressSearchState(sessionToken: _newSessionToken());
  }

  void onQueryChanged(String query) {
    state = state.copyWith(query: query, clearError: true);
    _debounceTimer?.cancel();

    if (query.trim().isEmpty) {
      state = state.copyWith(suggestions: const [], isSearching: false);
      return;
    }

    _debounceTimer = Timer(_debounce, () => _search(query));
  }

  Future<void> _search(String query) async {
    final generation = ++_requestGeneration;
    state = state.copyWith(isSearching: true, clearError: true);
    try {
      final suggestions =
          await ref.read(addressSearchProviderProvider).autocomplete(
                input: query,
                sessionToken: state.sessionToken,
              );
      // A newer search started while this one was in flight — discard a
      // stale result rather than racing it against a fresher one.
      if (generation != _requestGeneration) return;
      state = state.copyWith(suggestions: suggestions, isSearching: false);
    } catch (_) {
      if (generation != _requestGeneration) return;
      state = state.copyWith(
        isSearching: false,
        error: 'Adres önerileri alınamadı. Lütfen tekrar deneyin.',
      );
    }
  }

  /// Call after a suggestion is selected/resolved — retires the current
  /// session token (Google's own session-billing model: a session ends
  /// once its Place Details call happens) and starts a fresh one for the
  /// next search.
  void retireSession() {
    state = state.copyWith(sessionToken: _newSessionToken());
  }

  /// A session token only needs to be *unique enough per device* to
  /// correlate one search sequence for Google's own session-billing model
  /// (Faz P.2 §12) — not a security credential, so `dart:math`'s
  /// `Random.secure()` (already available, no new dependency) is more
  /// than sufficient.
  String _newSessionToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

final addressSearchProvider =
    NotifierProvider.autoDispose<AddressSearchNotifier, AddressSearchState>(
  AddressSearchNotifier.new,
);
