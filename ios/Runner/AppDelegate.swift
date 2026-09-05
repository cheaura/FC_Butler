import Flutter
import UIKit
import FirebaseMessaging

// Flutter 3.35+ 새 형식(FlutterImplicitEngineDelegate). 맥 빌드 도구가 자동 이관한 형식과 동일하게 맞춤 (2026-09-05).
// 플러그인 등록과 메서드 채널 생성은 didInitializeImplicitFlutterEngine에서 한다
// (UIScene 수명주기에서는 didFinishLaunching 시점에 window가 nil이라 옛 방식은 충돌 위험).
//
// APNs 등록 보강 (1.0.9+12 실기: 30초 동안 등록 성공/실패 콜백이 하나도 오지 않음 = '요청이 나가지 않았거나 응답이 없음'):
//  - firebase_messaging 플러그인은 UIApplicationDidFinishLaunchingNotification 관찰자 안에서만
//    registerForRemoteNotifications()와 앱 대리자 등록을 수행한다. 그 시점을 놓치면 등록이 영영 안 된다.
//    → 여기서 직접 registerForRemoteNotifications()를 호출한다(여러 번 불러도 무해).
//  - 토큰이 오면 Firebase Messaging에 직접 넘긴다(플러그인 대리자 등록이 빠졌어도 FCM 토큰 발급 가능).
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // APNs 등록 결과를 Dart(FCMService)에 알리기 위한 채널
  // Dart가 물어보면(getApnsStatus) 돌려주며, 결과가 오면 바로 밀어 넣는다(apnsStatus).
  private var apnsStatus: [String: Any] = ["state": "pending"]
  private var apnsChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let ok = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    // APNs 등록을 직접 요청 — 알림 권한과 무관하게 기기 토큰이 발급되며, 실패 시 didFail 콜백으로 이유가 온다
    application.registerForRemoteNotifications()
    apnsStatus["requested"] = true
    apnsStatus["requestedAt"] = ISO8601DateFormatter().string(from: Date())
    return ok
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

  // APNs 등록 성공 — Firebase Messaging에 직접 전달 + super(플러그인 대리자 체인)도 유지
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    apnsStatus["state"] = "registered"
    apnsStatus["tokenLength"] = deviceToken.count
    apnsStatus["registeredAt"] = ISO8601DateFormatter().string(from: Date())
    apnsChannel?.invokeMethod("apnsStatus", arguments: apnsStatus)
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  // APNs 등록 실패 — 원인 문구(예: no valid 'aps-environment' entitlement string found)를 Dart로 전달
  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    let ns = error as NSError
    apnsStatus["state"] = "failed"
    apnsStatus["error"] = "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
    apnsChannel?.invokeMethod("apnsStatus", arguments: apnsStatus)
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
}
