import 'dart:io' show Platform;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'error_reporter.dart';

/// 백그라운드 메시지 핸들러 (top-level 함수여야 함)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('[FCM Background] 메시지 수신: ${message.notification?.title}');
}

/// FCM 푸시 알림 서비스.
///
/// 2026-09-04 iOS 미수신 수정 (원인: 서버에 옛 FCButler 앱 토큰만 남고 Panenka 아이폰 앱이 토큰을 한 번도 등록 못 함):
///  - iOS는 APNs 토큰이 준비된 뒤에야 FCM 토큰을 받을 수 있는데(iOS SDK 10.4+ 필수) 앱 시작 직후 요청이 실패하면서
///    초기화 전체가 중단돼 리스너 등록·토큰 전송이 모두 빠졌다. → 리스너를 먼저 걸고, iOS는 APNs 토큰을 기다린 뒤 발급.
///  - 로그인·자동로그인 어느 경로든 토큰이 비어 있으면 그 자리에서 다시 발급해 전송하고, '자동 로그인' 저장값이 없어도
///    ApiService의 현재 토큰으로 전송한다.
///  - iOS 포그라운드는 시스템 표시 옵션을 켠다(로컬 알림 중복 생성 안 함). Android는 기존대로 로컬 알림.
///  - 토큰 등록 시 기기 종류·앱 버전·권한 상태를 함께 보내 서버 로그에서 바로 구분되게 한다.
class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  String? _fcmToken;
  String? _lastSentToken; // 같은 토큰 중복 전송 방지 (기기당 한 번)
  bool _isInitialized = false;
  bool _listenersBound = false;
  AuthorizationStatus _authStatus = AuthorizationStatus.notDetermined;

  /// FCM 초기화 — 권한 요청 → 로컬 알림 준비 → 리스너 등록 → (iOS) 포그라운드 표시 → 토큰 발급 시도
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 알림 권한 요청 (거부돼도 리스너·토큰 준비는 계속 — 설정에서 켜면 바로 동작)
      final NotificationSettings settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      _authStatus = settings.authorizationStatus;
      if (_authStatus != AuthorizationStatus.authorized) {
        print('[FCM] 알림 권한 미허용: $_authStatus');
      }

      await _initializeLocalNotifications();
      _bindListeners();

      // iOS: 앱이 떠 있을 때도 시스템이 배너·소리·배지를 표시 (기본값은 표시 안 함)
      if (Platform.isIOS) {
        await _firebaseMessaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      _isInitialized = true;
      print('[FCM] 초기화 완료 (권한: $_authStatus)');
    } catch (e, st) {
      print('[FCM] 초기화 실패: $e');
      ErrorReporter.report(e, st, context: 'FCM 초기화');
    }

    // 토큰 발급은 초기화 성패와 분리 (iOS는 APNs 토큰 대기)
    await _obtainToken();
  }

  /// 리스너 등록 (한 번만). getToken 실패와 무관하게 항상 등록되도록 분리.
  void _bindListeners() {
    if (_listenersBound) return;
    _listenersBound = true;

    // 토큰 갱신 → 로그인 상태면 서버 전송
    _firebaseMessaging.onTokenRefresh.listen((newToken) {
      print('[FCM] 토큰 갱신: $newToken');
      _fcmToken = newToken;
      _sendTokenToServer(newToken);
    });

    // 포그라운드 메시지 수신 — Android만 로컬 알림 표시 (iOS는 시스템 표시 옵션으로 처리)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('[FCM Foreground] 메시지 수신: ${message.notification?.title}');
      if (!Platform.isIOS) _showNotification(message);
    });

    // 백그라운드에서 알림 클릭 시
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('[FCM] 알림 클릭: ${message.notification?.title}');
    });

    // 백그라운드 메시지 핸들러 등록
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  /// FCM 토큰 발급. iOS는 APNs 토큰이 올 때까지 최대 [waitSeconds]초 대기한 뒤 요청한다.
  Future<String?> _obtainToken({int waitSeconds = 10}) async {
    try {
      if (Platform.isIOS) {
        String? apns;
        final deadline = DateTime.now().add(Duration(seconds: waitSeconds));
        while (apns == null && DateTime.now().isBefore(deadline)) {
          apns = await _firebaseMessaging.getAPNSToken();
          if (apns == null) await Future.delayed(const Duration(milliseconds: 500));
        }
        if (apns == null) {
          print('[FCM] APNs 토큰 미수신 (${waitSeconds}s 대기) — FCM 토큰 발급 보류');
          ErrorReporter.report(
              StateError('APNs 토큰 미수신 ${waitSeconds}s (권한: $_authStatus)'), null,
              context: 'FCM 토큰 발급');
          return _fcmToken;
        }
      }
      _fcmToken = await _firebaseMessaging.getToken();
      print('[FCM] 토큰 발급: $_fcmToken');
      return _fcmToken;
    } catch (e, st) {
      print('[FCM] 토큰 발급 실패: $e');
      ErrorReporter.report(e, st, context: 'FCM 토큰 발급');
      return _fcmToken;
    }
  }

  /// 로컬 알림 초기화
  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        print('[FCM] 로컬 알림 클릭: ${response.payload}');
      },
    );

    // Android 알림 채널 생성
    const androidChannel = AndroidNotificationChannel(
      'fc_macro_high_importance', // 채널 ID
      'Panenka 중요 알림', // 채널 이름
      description: 'Panenka 상태 알림',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  /// 알림 표시 (Android 포그라운드 전용)
  Future<void> _showNotification(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;

    if (notification != null) {
      await _notificationsPlugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'fc_macro_high_importance',
            'Panenka 중요 알림',
            channelDescription: 'Panenka 상태 알림',
            importance: Importance.high,
            priority: Priority.high,
            showWhen: true,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );
    }
  }

  /// 로그인 토큰 확보: SharedPreferences('auto login' 저장값) → 없으면 ApiService 현재 세션 토큰
  Future<String?> _resolveAuthToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('auth_token');
      if (saved != null && saved.isNotEmpty) return saved;
    } catch (_) {}
    return ApiService().token;
  }

  /// 서버에 FCM 토큰 전송 (기기 종류·앱 버전·권한 상태 동봉)
  Future<bool> _postToken(String fcmToken, String authToken) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serverUrl = prefs.getString('server_url') ?? ApiService.baseUrl;

      final response = await http
          .post(
            Uri.parse('$serverUrl/api/user/fcm_token'),
            headers: {
              'Authorization': 'Bearer $authToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'fcm_token': fcmToken,
              'platform': ErrorReporter.platform,
              'app_version': ErrorReporter.appVersion,
              'build': ErrorReporter.build,
              'permission': _authStatus.name,
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        _lastSentToken = fcmToken;
        print('[FCM] 토큰 서버 전송 성공');
        return true;
      }
      print('[FCM] 토큰 서버 전송 실패: ${response.statusCode}');
      return false;
    } catch (e) {
      print('[FCM] 토큰 서버 전송 오류: $e');
      return false;
    }
  }

  /// 서버에 FCM 토큰 전송 (내부용 - 토큰 갱신 시). 로그인 토큰이 없으면 보류.
  Future<void> _sendTokenToServer(String token) async {
    final auth = await _resolveAuthToken();
    if (auth == null || auth.isEmpty) {
      print('[FCM] 서버 토큰이 없어 FCM 토큰 전송 보류 (로그인 후 전송)');
      return;
    }
    await _postToken(token, auth);
  }

  /// 서버에 FCM 토큰 전송 (공개 메서드 - 로그인·자동로그인 직후 호출용)
  /// 토큰이 아직 없으면 이 자리에서 발급(iOS는 APNs 대기)한 뒤 보낸다.
  Future<void> sendTokenToServerWithAuth(String authToken) async {
    try {
      _fcmToken ??= await _obtainToken();
      if (_fcmToken == null) {
        print('[FCM] FCM 토큰 발급 실패 — 전송 생략');
        return;
      }
      await _postToken(_fcmToken!, authToken);
    } catch (e) {
      print('[FCM] 토큰 서버 전송 오류: $e');
    }
  }

  /// FCM 토큰 가져오기 및 서버 전송 (로그인 화면 경로)
  Future<String?> getTokenAndSendToServer() async {
    _fcmToken ??= await _obtainToken();
    if (_fcmToken != null && _fcmToken != _lastSentToken) {
      await _sendTokenToServer(_fcmToken!);
    }
    return _fcmToken;
  }

  /// FCM 토큰 반환
  String? get token => _fcmToken;

  /// 알림 권한 상태 (더보기·진단용)
  AuthorizationStatus get authorizationStatus => _authStatus;
}
