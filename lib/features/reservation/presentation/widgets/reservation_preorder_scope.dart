import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../cart/domain/models/cart_item.dart';
import '../../../cart/presentation/providers/cart_provider.dart';
import '../providers/preorder_cart_provider.dart';

/// Hosts the optional-preorder sub-flow (menu browsing, product detail,
/// Bowl Builder) in its own nested [Navigator], inside a [ProviderScope]
/// that gives this subtree its own fresh, independent [CartNotifier]
/// instance bound to the *name* [cartProvider] — Faz R.2 D4. Every screen
/// pushed onto [child]'s own `Navigator.of(context)` (which resolves to
/// *this* nested Navigator, being the nearest ancestor) — including the
/// existing, unmodified `ProductDetailScreen`/`BowlBuilderScreen`, both of
/// which hardcode `ref.read(cartProvider.notifier)` — writes into this
/// isolated instance purely by virtue of where in the widget tree it was
/// pushed from, never the app's real shopping cart.
///
/// (`cartProvider.overrideWithProvider(preorderCartProvider)` — true
/// provider aliasing, one instance under two names — was the first design
/// tried here; it is deprecated in this Riverpod version. Instead, the
/// nested scope's `cartProvider` is a genuinely separate instance, and
/// [_PreorderCartBridge] below mirrors every change from it into the
/// always-outer-visible [preorderCartProvider] the rest of the reservation
/// flow (review step, submit payload) actually reads — same externally
/// observable effect, without a deprecated API.)
class ReservationPreorderScope extends StatelessWidget {
  const ReservationPreorderScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [cartProvider.overrideWith(CartNotifier.new)],
      child: _PreorderCartBridge(
        outerContainer: ProviderScope.containerOf(context, listen: false),
        child: Navigator(
          onGenerateRoute: (settings) {
            return MaterialPageRoute(builder: (context) => child);
          },
        ),
      ),
    );
  }
}

/// Mirrors the nested (scoped) [cartProvider]'s state into the outer
/// [preorderCartProvider] on every change, using the outer
/// [ProviderContainer] captured *before* entering the nested [ProviderScope]
/// — this is the one place the two are bridged; everything else (the
/// pushed menu/product-detail/bowl-builder screens, the outer review step)
/// only ever reads/writes whichever of the two names it already knows
/// about.
class _PreorderCartBridge extends ConsumerStatefulWidget {
  const _PreorderCartBridge(
      {required this.outerContainer, required this.child});

  final ProviderContainer outerContainer;
  final Widget child;

  @override
  ConsumerState<_PreorderCartBridge> createState() =>
      _PreorderCartBridgeState();
}

class _PreorderCartBridgeState extends ConsumerState<_PreorderCartBridge> {
  ProviderSubscription<List<CartItem>>? _subscription;

  @override
  void initState() {
    super.initState();
    // `ref` here resolves through the nested (scoped) ProviderScope this
    // widget is built inside — its own `cartProvider` reads the isolated
    // instance, not the app's real one.
    //
    // No `fireImmediately: true` here: writing into the *outer* container's
    // `preorderCartProvider` synchronously from `initState` — i.e. while
    // the widget tree is still building — trips Riverpod's build-phase
    // safety check ("Tried to modify a provider while the widget tree was
    // building"), regardless of which container is targeted. The initial
    // sync is instead scheduled for right after this frame finishes.
    _subscription = ref.listenManual<List<CartItem>>(
      cartProvider,
      (previous, next) {
        widget.outerContainer
            .read(preorderCartProvider.notifier)
            .replaceAll(next);
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.outerContainer
          .read(preorderCartProvider.notifier)
          .replaceAll(ref.read(cartProvider));
    });
  }

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
