import Flutter
import UIKit

// Flutter 3.35+ 새 형식(FlutterImplicitEngineDelegate). 맥 빌드 도구가 자동 이관한 형식과 동일하게 맞춤 (2026-09-05).
// 플러그인 등록과 메서드 채널 생성은 didInitializeImplicitFlutterEngine에서 한다
// (UIScene 수명주기에서는 didFinishLaunching 시점에 window가 nil이라 옛 방식은 충돌 위험).
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // APNs 등록 결과를 Dart(FCMService)에 알리기 위한 채널 (1.0.9+12)
  // 등록 실패 이유는 firebase_messaging 플러그인이 NSLog로만 남겨 기기 밖에서 볼 수 없었다.
  // 여기서 성공/실패를 기록해 두고, Dart가 물어보면(getApnsStatus) 돌려주며 결과가 오면 바로 밀어 넣는다(apnsStatus).
  private var apnsStatus: [String: Any] = ["state": "pending"]
  private var apnsChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "panenka/apns",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      if call.method == "getApnsStatus" {
        result(self?.apnsStatus ?? ["state": "unknown"])
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    apnsChannel = channel
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
