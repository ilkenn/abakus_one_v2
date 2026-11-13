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
    // 2026-11-12 (Faz 3c) — lets flutter_local_notifications / FCM present
    // courier-pool notifications while the app is in the foreground.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AbakusScreenCapture") {
      ScreenCaptureShield.shared.attach(messenger: registrar.messenger())
    }
  }
}

/// ADR-085 stage 2 (KVKK) — best effort on iOS: a single screenshot cannot be
/// blocked there, but while a staff screen is protected and the screen is
/// being recorded or mirrored, a blank cover hides the content.
final class ScreenCaptureShield {
  static let shared = ScreenCaptureShield()

  private var channel: FlutterMethodChannel?
  private var protected = false
  private var cover: UIView?

  func attach(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "abakus/screen_capture", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setProtected" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.protected = (call.arguments as? Bool) ?? false
      self?.update()
      result(nil)
    }
    self.channel = channel
    NotificationCenter.default.addObserver(
      forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.update() }
  }

  private func keyWindow() -> UIWindow? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
  }

  private func update() {
    let hide = protected && UIScreen.main.isCaptured
    if hide, cover == nil, let window = keyWindow() {
      let view = UIView(frame: window.bounds)
      view.backgroundColor = .black
      view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      window.addSubview(view)
      cover = view
    } else if !hide {
      cover?.removeFromSuperview()
      cover = nil
    }
  }
}
