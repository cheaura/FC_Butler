import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _isNotificationInitialized = false;

  /// 알림 초기화
  Future<void> _initializeNotifications() async {
    if (_isNotificationInitialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        print('[알림 클릭] ${response.payload}');
      },
    );

    // Android 13+ 알림 권한 요청
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _isNotificationInitialized = true;
    print('[SocketService] 알림 초기화 완료');
  }

  /// WebSocket 연결 및 알림 초기화
  Future<void> connect(String token, String serverUrl) async {
    // 알림 초기화
    await _initializeNotifications();

    // 기존 연결이 있으면 종료
    if (_socket != null && _socket!.connected) {
      _socket!.disconnect();
    }

    // WebSocket 연결
    _socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'reconnection': true,
      'reconnectionDelay': 1000,
      'reconnectionDelayMax': 5000,
      'reconnectionAttempts': double.infinity,
      'timeout': 10000,
    });

    _socket!.connect();

    _socket!.on('connected', (data) {
      print('[SocketService] 연결 성공: $data');
      // 서버 인증
      _socket!.emit('authenticate', {'token': token});
    });

    _socket!.on('authenticated', (data) {
      print('[SocketService] 인증 성공: ${data['username']}');
    });

    // 🚨 알림 수신 및 표시
    _socket!.on('macro_notification', (data) {
      final title = data['title'] ?? '알림';
      final body = data['body'] ?? '';
      print('[SocketService] 알림 수신: $title - $body');
      
      // 안드로이드 알림 표시
      _showNotification(title, body);
    });

    _socket!.on('auth_error', (data) {
      print('[SocketService] 인증 실패: ${data['message']}');
    });

    _socket!.on('connect_error', (data) {
      print('[SocketService] 연결 오류: $data');
    });

    _socket!.on('disconnect', (data) {
      print('[SocketService] 연결 종료: $data');
    });
  }

  /// 로컬 알림 표시
  Future<void> _showNotification(String title, String body) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'fc_macro_channel', // 채널 ID
        'FC Butler 알림', // 채널 이름
        channelDescription: 'Panenka 상태 알림',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        icon: '@mipmap/ic_launcher',
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notificationsPlugin.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000, // 고유 ID
        title,
        body,
        notificationDetails,
        payload: '$title|$body',
      );

      print('[SocketService] 알림 표시 완료: $title');
    } catch (e) {
      print('[SocketService] 알림 표시 오류: $e');
    }
  }

  /// WebSocket 연결 상태 확인
  bool get isConnected => _socket?.connected ?? false;

  /// WebSocket 연결 해제
  void disconnect() {
    _socket?.disconnect();
    _socket = null;
    print('[SocketService] 연결 해제');
  }
}
