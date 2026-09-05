import 'dart:async';
import 'dart:io' show Platform;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel, MissingPluginException;
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
///
/// 2026-09-05 (1.0.9+12) 앱 시작 지연·APNs 원인 진단:
///  - 1.0.9+11 실기(TestFlight)에서 APNs 토큰이 10초 안에 오지 않아(오류 보고 7회, 권한 authorized) main()이 runApp 전에
///    10초, 스플래시가 다시 10초를 기다리며 앱 실행이 20초 이상 걸렸다. → 토큰 발급 대기는 어디서도 화면을 막지 않는다.
///    발급은 백그라운드 한 줄기(_ensureToken)로만 돌고, 로그인/자동로그인은 인증 토큰만 맡겨 두면 FCM 토큰이 준비되는
///    순간 서버로 보낸다(onTokenRefresh 포함).
///  - APNs 등록 실패 이유는 지금까지 네이티브 콘솔(NSLog)에만 남아 기기 밖에서 알 수 없었다. → AppDelegate가
///    등록 성공/실패 결과를 'panenka/apns' 채널로 넘기고, 여기서 실패 원인 문구를 오류 보고에 실어 서버에서 본다.
class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  /// iOS AppDelegate ↔ Dart: APNs 등록 결과 (getApnsStatus / apnsStatus)
  static const MethodChannel _apnsChannel = MethodChannel('panenka/apns');

  String? _fcmToken;
  String? _lastSentToken; // 같은 토큰 중복 전송 방지 (기기당 한 번)
  String? _pendingAuthToken; // FCM 토큰 준비 전에 로그인이 끝났을 때 보관 → 토큰이 오면 전송
  Future<String?>? _tokenFuture; // 진행 중인 발급 (중복 대기 방지)
  bool _isInitialized = false;
  bool _listenersBound = false;
  AuthorizationStatus _authStatus = AuthorizationStatus.notDetermined;
  Map<String, dynamic>? _apnsStatus; // 네이티브가 알려준 APNs 등록 상태 (iOS)

  /// FCM 초기화 — 권한 요청 → 로컬 알림 준비 → 리스너 등록 → (iOS) 포그라운드 표시.
  /// 토큰 발급은 백그라운드로 넘기고 바로 돌아온다 (앱 시작을 막지 않음).
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    try {
      if (Platform.isIOS) {
        _apnsChannel.setMethodCallHandler(_onApnsCall);
      }

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

      print('[FCM] 초기화 완료 (권한: $_authStatus)');
    } catch (e, st) {
      print('[FCM] 초기화 실패: $e');
      ErrorReporter.report(e, st, context: 'FCM 초기화');
    }

    // 토큰 발급은 기다리지 않는다 (iOS APNs 대기가 화면을 막던 문제)
    unawaited(_ensureToken());
  }

  /// 리스너 등록 (한 번만). getToken 실패와 무관하게 항상 등록되도록 분리.
  void _bindListeners() {
    if (_listenersBound) return;
    _listenersBound = true;

    // 토큰 발급·갱신 → 로그인 상태면 서버 전송 (APNs가 늦게 와서 FCM 토큰이 나중에 생기는 경우도 여기로 온다)
    _firebaseMessaging.onTokenRefresh.listen((newToken) {
      print('[FCM] 토큰 갱신: $newToken');
      _fcmToken = newToken;
      unawaited(_flushPending());
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

  // ───────────────────────── APNs 등록 상태 (iOS 네이티브 ↔ Dart) ─────────────────────────

  /// AppDelegate가 APNs 등록 결과를 밀어 넣을 때 (apnsStatus: {state: registered|failed, error?})
  Future<dynamic> _onApnsCall(MethodCall call) async {
    if (call.method == 'apnsStatus' && call.arguments is Map) {
      _apnsStatus = Map<String, dynamic>.from(call.arguments as Map);
      print('[FCM] APNs 등록 상태(네이티브): $_apnsStatus');
      if (_apnsStatus!['state'] == 'failed') {
        // 실패 원인 문구를 그대로 서버에 남긴다 (예: no valid 'aps-environment' entitlement string found)
        ErrorReporter.report(
            StateError('APNs 등록 실패: ${_apnsStatus!['error']} (권한: $_authStatus)'), null,
            context: 'APNs 등록');
      }
    }
    return null;
  }

  /// 네이티브에 저장된 APNs 등록 상태를 물어본다 (AppDelegate 미갱신 빌드면 null)
  Future<Map<String, dynamic>?> _queryApnsStatus() async {
    if (!Platform.isIOS) return null;
    try {
      final r = await _apnsChannel.invokeMethod<dynamic>('getApnsStatus');
      if (r is Map) _apnsStatus = Map<String, dynamic>.from(r);
    } on MissingPluginException {
      // 구 AppDelegate — 채널 없음
    } catch (e) {
      print('[FCM] APNs 상태 조회 실패: $e');
    }
    return _apnsStatus;
  }

  String _describeApns(Map<String, dynamic>? st) {
    if (st == null) return '네이티브 상태 없음';
    final state = st['state'];
    final err = st['error'];
    final requested = st['requested'] == true ? ' 요청함' : ' 요청기록없음';
    return err == null ? '$state$requested' : '$state$requested: $err';
  }

  // ───────────────────────── 토큰 발급 ─────────────────────────

  /// FCM 토큰을 확보한다. 이미 있으면 즉시, 발급 중이면 그 결과를 함께 기다린다 (한 줄기만 돈다).
  Future<String?> _ensureToken() {
    if (_fcmToken != null) return Future.value(_fcmToken);
    return _tokenFuture ??= _obtainToken().whenComplete(() => _tokenFuture = null);
  }

  /// FCM 토큰 발급. iOS는 APNs 토큰이 올 때까지 최대 [waitSeconds]초 대기한 뒤 요청한다.
  /// 호출자는 이 Future를 화면 흐름에서 기다리지 말 것 (백그라운드 전용).
  Future<String?> _obtainToken({int waitSeconds = 30}) async {
    try {
      if (Platform.isIOS) {
        String? apns;
        final deadline = DateTime.now().add(Duration(seconds: waitSeconds));
        while (apns == null && DateTime.now().isBefore(deadline)) {
          apns = await _firebaseMessaging.getAPNSToken();
          if (apns == null) {
            // 네이티브가 이미 '실패'를 확정했으면 더 기다릴 이유가 없다
            if (_apnsStatus?['state'] == 'failed') break;
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }
        if (apns == null) {
          final st = await _queryApnsStatus();
          print('[FCM] APNs 토큰 미수신 (${waitSeconds}s 대기) — FCM 토큰 발급 보류 / ${_describeApns(st)}');
          ErrorReporter.report(
              StateError('APNs 토큰 미수신 ${waitSeconds}s (권한: $_authStatus, 네이티브: ${_describeApns(st)})'),
              null,
              context: 'FCM 토큰 발급');
          return null;
        }
      }
      _fcmToken = await _firebaseMessaging.getToken();
      print('[FCM] 토큰 발급: $_fcmToken');
      await _flushPending();
      return _fcmToken;
    } catch (e, st) {
      print('[FCM] 토큰 발급 실패: $e');
      ErrorReporter.report(e, st, context: 'FCM 토큰 발급');
      return null;
    }
  }

  /// FCM 토큰이 준비됐을 때: 맡겨 둔 인증 토큰(또는 저장/세션 토큰)으로 서버에 전송
  Future<void> _flushPending() async {
    final fcm = _fcmToken;
    if (fcm == null) return;
    final auth = _pendingAuthToken ?? await _resolveAuthToken();
    if (auth == null || auth.isEmpty) {
      print('[FCM] 서버 토큰이 없어 FCM 토큰 전송 보류 (로그인 후 전송)');
      return;
    }
    if (_pendingAuthToken == null && fcm == _lastSentToken) return; // 갱신 없는 재호출
    _pendingAuthToken = null;
    await _postToken(fcm, auth);
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

  /// 서버에 FCM 토큰 전송 (공개 메서드 - 로그인·자동로그인 직후 호출용)
  /// FCM 토큰이 있으면 바로 보내고, 없으면 인증 토큰만 맡겨 두고 즉시 돌아온다
  /// (발급이 끝나는 순간 백그라운드에서 전송). 화면 흐름을 막지 않는다.
  Future<void> sendTokenToServerWithAuth(String authToken) async {
    try {
      final fcm = _fcmToken;
      if (fcm != null) {
        await _postToken(fcm, authToken);
        return;
      }
      _pendingAuthToken = authToken;
      print('[FCM] FCM 토큰 미발급 — 인증 토큰 보관 후 발급 완료 시 전송');
      unawaited(_ensureToken());
    } catch (e) {
      print('[FCM] 토큰 서버 전송 오류: $e');
    }
  }

  /// FCM 토큰 가져오기 및 서버 전송 (로그인 화면 경로). 화면 흐름을 막지 않는다.
  Future<String?> getTokenAndSendToServer() async {
    final auth = await _resolveAuthToken();
    if (auth != null && auth.isNotEmpty) {
      await sendTokenToServerWithAuth(auth);
    } else {
      unawaited(_ensureToken());
    }
    return _fcmToken;
  }

  /// FCM 토큰 반환
  String? get token => _fcmToken;

  /// 알림 권한 상태 (더보기·진단용)
  AuthorizationStatus get authorizationStatus => _authStatus;

  /// APNs 등록 상태 (iOS 진단용)
  Map<String, dynamic>? get apnsStatus => _apnsStatus;
}
