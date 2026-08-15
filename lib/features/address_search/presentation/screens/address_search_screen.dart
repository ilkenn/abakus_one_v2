import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../data/address_search_exception.dart';
import '../../domain/models/address_suggestion.dart';
import '../providers/address_search_provider.dart';

/// Faz P.2 §3 / Faz P.2.1.2 UX correction — the autocomplete search
/// **subflow**. Debounced (via [AddressSearchNotifier]), TR-restricted +
/// Istanbul-biased server-side (`searchAddressAutocomplete`). Map-first
/// address creation (`MapFirstAddressScreen`) is the canonical *primary*
/// flow — this screen is its secondary "Adres Ara" convenience: selecting
/// a suggestion **resolves it server-side and pops with the resulting
/// [LatLng]** rather than navigating onward itself. The caller (the map
/// screen) re-centers its own camera there, and that camera move's own
/// `onCameraIdle` → `reverseGeocodeAddressPoint` is what actually
/// (re-)confirms the final address — the same single resolution pipeline
/// every other path in the map-first flow uses. This screen therefore
/// never itself produces address-authorization evidence, only a
/// candidate point — matching "no duplicate address authority or
/// separate save paths" (`docs/decisions.md` Faz P.2.1.2).
class AddressSearchScreen extends ConsumerStatefulWidget {
  const AddressSearchScreen({super.key});

  @override
  ConsumerState<AddressSearchScreen> createState() =>
      _AddressSearchScreenState();
}

class _AddressSearchScreenState extends ConsumerState<AddressSearchScreen> {
  final _controller = TextEditingController();
  bool _isResolvingSelection = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _selectSuggestion(AddressSuggestion suggestion) async {
    final sessionToken = ref.read(addressSearchProvider).sessionToken;
    ref.read(addressSearchProvider.notifier).retireSession();
    setState(() => _isResolvingSelection = true);
    try {
      final resolved =
          await ref.read(addressSearchProviderProvider).resolvePlace(
                placeId: suggestion.providerPlaceId,
                sessionToken: sessionToken,
              );
      if (!mounted) return;
      if (resolved.latitude == null || resolved.longitude == null) {
        setState(() {
          _isResolvingSelection = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bu adres için konum bulunamadı.')),
        );
        return;
      }
      Navigator.of(context)
          .pop(LatLng(resolved.latitude!, resolved.longitude!));
    } on AddressSearchException catch (error) {
      if (!mounted) return;
      setState(() => _isResolvingSelection = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(addressSearchProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Adres Ara'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: (value) => ref
                  .read(addressSearchProvider.notifier)
                  .onQueryChanged(value),
              decoration: const InputDecoration(
                hintText: 'Mahalle, cadde/sokak veya bina ara',
                prefixIcon: Icon(Icons.search),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: AppRadius.kMedium,
                  borderSide: BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppRadius.kMedium,
                  borderSide: BorderSide(color: AppColors.border),
                ),
              ),
            ),
          ),
          if (state.isSearching)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              ),
            ),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                state.error!,
                style: AppTypography.bodySmall.copyWith(color: AppColors.error),
              ),
            ),
          Expanded(
            child: state.suggestions.isEmpty
                ? (state.query.trim().isEmpty
                    ? const EmptyView(
                        icon: Icons.location_on_outlined,
                        message: 'Adres aramaya baslayin.',
                      )
                    : (state.isSearching
                        ? const SizedBox.shrink()
                        : const EmptyView(
                            icon: Icons.search_off,
                            message: 'Sonuc bulunamadi.',
                          )))
                : ListView.separated(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    itemCount: state.suggestions.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: AppColors.divider, height: 1),
                    itemBuilder: (context, index) {
                      final suggestion = state.suggestions[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.location_on_outlined,
                          color: AppColors.primary,
                        ),
                        title: Text(
                          suggestion.text,
                          style: AppTypography.bodyMedium,
                        ),
                        trailing: _isResolvingSelection
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : null,
                        onTap: _isResolvingSelection
                            ? null
                            : () => _selectSuggestion(suggestion),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
