import 'package:socket_io_client/socket_io_client.dart' as IO;
// import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // 제거됨

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;

  /// WebSocket 연결 및 알림 초기화
  Future<void> connect(String token, String serverUrl) async {
    // WebSocket-only 알림 처리 (로컬 notification 플러그인 제거됨)

    // 기존 연결이 있으면 종료
    if (_socket != null && _socket!.connected) {
      _socket!.disconnect();
    }

    // WebSocket 연결
    _socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'reconnection': true,
      'reconnectionDelay': 2000,
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

    // 🚨 알림 수신
    _socket!.on('macro_notification', (data) {
      final title = data['title'] ?? '알림';
      final body = data['body'] ?? '';
      print('[SocketService] 알림 수신: $title - $body');
      // TODO: 앱 내부 UI 알림/토스트로 노출하거나, 필요시 로컬 알림 구현
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

  /// 로컬 알림 표시는 제거되었습니다. WebSocket 콜백에서 처리합니다.

  /// WebSocket 연결 상태 확인
  bool get isConnected => _socket?.connected ?? false;

  /// WebSocket 연결 해제
  void disconnect() {
    _socket?.disconnect();
    _socket = null;
    print('[SocketService] 연결 해제');
  }
}
