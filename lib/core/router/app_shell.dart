// Deliberately empty for now.
//
// A persistent-bottom-nav shell (`StatefulShellRoute.indexedStack`) is the
// natural `go_router` fit for `MainNavigationScreen`'s tab bar (see
// ADR-006), but wiring it up means giving each tab its own nested
// navigator and moving `MainNavigationScreen`'s existing internal
// tab-switching state out to the route tree — a redesign of that screen,
// not a router foundation. P1-010 scopes `/main` as a single opaque
// `GoRoute` instead (see `app_router.dart`) and leaves that migration for
// a later, separately approved task.
