import '../models/address_suggestion.dart';
import '../models/resolved_address.dart';

/// Generic address-search abstraction — Faz P.2. **Domain must not depend
/// on Google SDK response classes** (explicit instruction): this
/// interface and both model types it returns
/// ([AddressSuggestion]/[ResolvedAddress]) are provider-neutral. The
/// Google-specific implementation lives in `data/`
/// (`google_places_address_search_provider.dart`) and is the only file
/// that knows a provider named "Google" exists at all.
///
/// [autocomplete]/[resolvePlace] were the only two operations Faz P.2
/// needed. Faz P.2.1 adds the third, originally-conditional
/// responsibility, [reverseGeocode] — genuinely required once a customer
/// can drag a map pin: a moved pin's coordinates must never become
/// delivery-authorization truth directly, only via a fresh server-side
/// re-resolution (see [reverseGeocode]'s own doc comment).
abstract interface class AddressSearchProvider {
  /// Returns suggestions for [input] within one autocomplete session
  /// identified by [sessionToken] (a client-generated value reused across
  /// every keystroke of one search, then retired after [resolvePlace] is
  /// called — Faz P.2 §12's session-token cost-control requirement).
  /// Returns an empty list for empty/whitespace-only [input] without
  /// making a request — never an error.
  Future<List<AddressSuggestion>> autocomplete({
    required String input,
    required String sessionToken,
  });

  /// Resolves [placeId] (an [AddressSuggestion.providerPlaceId]) to a
  /// preview [ResolvedAddress], ending the autocomplete session identified
  /// by [sessionToken]. **Not authoritative** — see [ResolvedAddress]'s
  /// own doc comment; the actual save path re-resolves independently.
  Future<ResolvedAddress> resolvePlace({
    required String placeId,
    required String sessionToken,
  });

  /// Faz P.2.1 §2 — reverse-resolves a customer-adjusted map pin position
  /// ([latitude]/[longitude]) into a real, server-verified
  /// [ResolvedAddress]. Returns a [ResolvedAddress] with
  /// [ResolvedAddress.isSufficientlyResolved] `false` (never throws) when
  /// the point cannot be reverse-geocoded at all — the caller shows a
  /// friendly "bu konum çözümlenemedi" message rather than a hard error.
  /// **Not itself delivery-authorization evidence**, same as
  /// [resolvePlace] — the caller must still pass the returned
  /// [ResolvedAddress.providerPlaceId] through the normal save path
  /// (`SavedAddressRepository.save`), which independently re-resolves it
  /// again server-side. There is no path from a raw client-supplied
  /// coordinate directly into a saved address.
  Future<ResolvedAddress> reverseGeocode({
    required double latitude,
    required double longitude,
  });
}
