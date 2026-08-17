import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 백그라운드 메시지 핸들러 (top-level 함수여야 함)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('[FCM Background] 메시지 수신: ${message.notification?.title}');
}

class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _notificationsPlugin = 
      FlutterLocalNotificationsPlugin();
  
  String? _fcmToken;
  bool _isInitialized = false;

  /// FCM 초기화
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 알림 권한 요청
      NotificationSettings settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        print('[FCM] 알림 권한이 거부되었습니다');
        return;
      }

      // 로컬 알림 초기화
      await _initializeLocalNotifications();

      // FCM 토큰 가져오기
      _fcmToken = await _firebaseMessaging.getToken();
      print('[FCM] 토큰 발급: $_fcmToken');

      // 토큰 갱신 리스너 (저장만 하고 서버 전송은 로그인 후에)
      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        print('[FCM] 토큰 갱신: $newToken');
        _fcmToken = newToken;
        // 토큰 갱신 시에만 서버 전송 시도 (로그인되어 있으면 전송됨)
        _sendTokenToServer(newToken);
      });

      // 포그라운드 메시지 수신
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('[FCM Foreground] 메시지 수신: ${message.notification?.title}');
        _showNotification(message);
      });

      // 백그라운드에서 알림 클릭 시
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        print('[FCM] 알림 클릭: ${message.notification?.title}');
      });

      // 백그라운드 메시지 핸들러 등록
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      _isInitialized = true;
      print('[FCM] 초기화 완료');
    } catch (e) {
      print('[FCM] 초기화 실패: $e');
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

  /// 알림 표시
  Future<void> _showNotification(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

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

  /// 서버에 FCM 토큰 전송 (내부용 - 토큰 갱신 시)
  Future<void> _sendTokenToServer(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userToken = prefs.getString('auth_token');  // 'user_token' → 'auth_token' 변경
      final serverUrl = prefs.getString('server_url') ?? 'http://218.146.16.144:5000';

      if (userToken == null) {
        print('[FCM] 서버 토큰이 없어 FCM 토큰 전송 불가');
        return;
      }

      final response = await http.post(
        Uri.parse('$serverUrl/api/user/fcm_token'),
        headers: {
          'Authorization': 'Bearer $userToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'fcm_token': token}),
      );

      if (response.statusCode == 200) {
        print('[FCM] 토큰 서버 전송 성공');
      } else {
        print('[FCM] 토큰 서버 전송 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('[FCM] 토큰 서버 전송 오류: $e');
    }
  }

  /// 서버에 FCM 토큰 전송 (공개 메서드 - 로그인 후 호출용)
  /// ApiService의 토큰을 직접 받아서 사용
  Future<void> sendTokenToServerWithAuth(String authToken) async {
    try {
      if (_fcmToken == null) {
        print('[FCM] FCM 토큰이 아직 발급되지 않았습니다');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final serverUrl = prefs.getString('server_url') ?? 'http://218.146.16.144:5000';

      final response = await http.post(
        Uri.parse('$serverUrl/api/user/fcm_token'),
        headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'fcm_token': _fcmToken}),
      );

      if (response.statusCode == 200) {
        print('[FCM] 토큰 서버 전송 성공');
      } else {
        print('[FCM] 토큰 서버 전송 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('[FCM] 토큰 서버 전송 오류: $e');
    }
  }

  /// FCM 토큰 가져오기 및 서버 전송
  Future<String?> getTokenAndSendToServer() async {
    if (_fcmToken == null) {
      _fcmToken = await _firebaseMessaging.getToken();
      print('[FCM] 새 토큰 발급: $_fcmToken');
    }

    if (_fcmToken != null) {
      await _sendTokenToServer(_fcmToken!);
    }

    return _fcmToken;
  }

  /// FCM 토큰 반환
  String? get token => _fcmToken;
}
