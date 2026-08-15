import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Faz P.2.1 — Google Maps SDK for iOS. Reads the key Info.plist's
    // GMSApiKey entry resolved via Xcode build-setting substitution (see
    // Info.plist's own comment) — never a literal here. Missing/empty is
    // safe: GMSServices.provideAPIKey with an empty string simply leaves
    // the SDK uninitialized, which the Flutter-side map screen already
    // treats as an expected fallback case.
    if let mapsApiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
      !mapsApiKey.isEmpty
    {
      GMSServices.provideAPIKey(mapsApiKey)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
