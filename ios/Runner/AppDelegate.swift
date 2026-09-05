import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  // APNs 등록 결과를 Dart(FCMService)에 알리기 위한 채널 (2026-09-05, 1.0.9+12)
  // 등록 실패 이유는 firebase_messaging 플러그인이 NSLog로만 남겨 기기 밖에서 볼 수 없었다.
  // 여기서 성공/실패를 기록해 두고, Dart가 물어보면(getApnsStatus) 돌려주며 결과가 오면 바로 밀어 넣는다(apnsStatus).
  private var apnsStatus: [String: Any] = ["state": "pending"]
  private var apnsChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "panenka/apns", binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
        if call.method == "getApnsStatus" {
          result(self?.apnsStatus ?? ["state": "unknown"])
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      apnsChannel = channel
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // APNs 등록 성공 — super가 firebase_messaging 플러그인으로 토큰을 넘긴다 (반드시 호출)
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    apnsStatus = ["state": "registered", "tokenLength": deviceToken.count]
    apnsChannel?.invokeMethod("apnsStatus", arguments: apnsStatus)
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  // APNs 등록 실패 — 원인 문구(예: no valid 'aps-environment' entitlement string found)를 Dart로 전달
  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    let ns = error as NSError
    apnsStatus = [
      "state": "failed",
      "error": "\(ns.domain) \(ns.code): \(ns.localizedDescription)",
    ]
    apnsChannel?.invokeMethod("apnsStatus", arguments: apnsStatus)
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
}
