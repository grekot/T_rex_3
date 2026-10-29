import Flutter
import NetworkExtension
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var joinedSsid: String?
  private var joinedPrefix: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Sieć konfiguracyjna urządzenia bez Bluetooth `HA_<id>` (kontrakt pkt 9.4).
    // Wymaga uprawnienia „Hotspot Configuration” (Runner.entitlements).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HomeWifi") {
      let channel = FlutterMethodChannel(name: "pl.grekot.homeautomation/wifi", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { [weak self] call, result in
        self?.handle(call, result: result)
      }
    }
    // Otwarcie adresu w innej aplikacji (ntfy, przeglądarka - kontrakt pkt 3d).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HomeLinks") {
      let links = FlutterMethodChannel(name: "pl.grekot.homeautomation/links", binaryMessenger: registrar.messenger())
      links.setMethodCallHandler { call, result in
        guard call.method == "open" else {
          result(FlutterMethodNotImplemented)
          return
        }
        let args = call.arguments as? [String: Any] ?? [:]
        guard let text = args["url"] as? String, let url = URL(string: text) else {
          result(false)
          return
        }
        UIApplication.shared.open(url, options: [:]) { ok in result(ok) }
      }
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "joinAp":
      let args = call.arguments as? [String: Any] ?? [:]
      let passphrase = args["passphrase"] as? String ?? ""
      let configuration: NEHotspotConfiguration
      if let ssid = args["ssid"] as? String {
        configuration = NEHotspotConfiguration(ssid: ssid, passphrase: passphrase, isWEP: false)
        joinedSsid = ssid
      } else {
        let prefix = args["prefix"] as? String ?? "HA_"
        configuration = NEHotspotConfiguration(ssidPrefix: prefix, passphrase: passphrase, isWEP: false)
        joinedPrefix = prefix
      }
      configuration.joinOnce = true
      NEHotspotConfigurationManager.shared.apply(configuration) { error in
        DispatchQueue.main.async {
          if let error = error as NSError? {
            if error.domain == NEHotspotConfigurationErrorDomain,
               error.code == NEHotspotConfigurationError.alreadyAssociated.rawValue {
              result(nil)
            } else if error.domain == NEHotspotConfigurationErrorDomain,
                      error.code == NEHotspotConfigurationError.userDenied.rawValue {
              result(FlutterError(code: "cancelled", message: error.localizedDescription, details: nil))
            } else {
              result(FlutterError(code: "unavailable", message: error.localizedDescription, details: nil))
            }
          } else {
            result(nil)
          }
        }
      }
    case "releaseAp":
      if let ssid = joinedSsid {
        NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid)
      }
      // Sieć z prefiksem ma joinOnce - system zapomina ją sam po wyjściu z aplikacji.
      joinedSsid = nil
      joinedPrefix = nil
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
