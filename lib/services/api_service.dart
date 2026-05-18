import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'fcm_service.dart';

class ApiService {
  // 싱글톤 패턴
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();
  
  static const String baseUrl = 'http://218.146.16.144:5000';
  String? _token;
  String? _username;

  // Token getter
  String? get token => _token;
  String? get username => _username;

  // ===== 자동로그인 체크 (앱 시작 시 호출) =====
  Future<Map<String, dynamic>> checkAutoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getString('auth_token');
      final savedUsername = prefs.getString('username');
      final expiryTime = prefs.getInt('token_expiry');
      
      if (savedToken != null && savedUsername != null && expiryTime != null) {
        // 토큰 만료 시간 체크 (30일)
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now < expiryTime) {
          // 토큰 유효 - 서버에 토큰 검증 요청
          _token = savedToken;
          _username = savedUsername;
          
          // 토큰 유효성 검증 (서버에 간단한 요청)
          final response = await http.get(
            Uri.parse('$baseUrl/api/user/dashboard/status'),
            headers: {'Authorization': 'Bearer $_token'},
          ).timeout(Duration(seconds: 5));
          
          if (response.statusCode == 200) {
            return {'success': true, 'username': savedUsername};
          }
        }
      }
      
      // 자동로그인 실패 - 저장된 정보 삭제
      await clearAutoLogin();
      return {'success': false};
      
    } catch (e) {
      print('[자동로그인 체크 오류] $e');
      await clearAutoLogin();
      return {'success': false};
    }
  }

  // ===== 자동로그인 정보 저장 =====
  Future<void> saveAutoLogin(String token, String username) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final expiryTime = DateTime.now().add(Duration(days: 30)).millisecondsSinceEpoch;
      
      await prefs.setString('auth_token', token);
      await prefs.setString('username', username);
      await prefs.setInt('token_expiry', expiryTime);
      
      _token = token;
      _username = username;
      
      print('[자동로그인] 저장 완료: $username (만료: 30일 후)');
    } catch (e) {
      print('[자동로그인 저장 오류] $e');
    }
  }

  // ===== 자동로그인 정보 삭제 (로그아웃 시에만 사용) =====
  Future<void> clearAutoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');
      await prefs.remove('username');
      await prefs.remove('token_expiry');
      
      // 로그아웃이므로 메모리 토큰도 삭제
      _token = null;
      _username = null;
      
      print('[로그아웃] 모든 인증 정보 삭제 완료');
    } catch (e) {
      print('[자동로그인 삭제 오류] $e');
    }
  }

  Future<Map<String, dynamic>> login(String username, String password, bool rememberMe) async {
    try {
      print('[API] 로그인 시도: $username, 자동로그인: $rememberMe');
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/user/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'password': password,
          'remember_me': rememberMe,
        }),
      );

      final data = json.decode(response.body);
      print('[API] 로그인 응답: ${response.statusCode}, success: ${data['success']}');

      if (response.statusCode == 200 && data['success'] == true) {
        _token = data['token'];
        _username = username;
        print('[API] 토큰 설정 완료: ${_token != null ? "있음" : "없음"}, username: $_username');
        
        // 자동로그인 체크 시에만 SharedPreferences에 저장
        if (rememberMe) {
          await saveAutoLogin(data['token'], username);
          print('[API] 자동로그인 정보 저장 완료');
        }
        // 자동로그인 체크 안 함 → 아무것도 하지 않음 (SharedPreferences에 저장 안 함)
        
        // 로그인 성공 후 FCM 토큰 전송 (자동/수동 모두)
        try {
          await FCMService().sendTokenToServerWithAuth(data['token']);
          print('[API] FCM 토큰 전송 완료');
        } catch (e) {
          print('[API] FCM 토큰 전송 실패: $e');
        }
        
        return {'success': true, 'username': username};
      } else {
        return {
          'success': false,
          'message': data['message'] ?? '로그인 실패'
        };
      }
    } catch (e) {
      print('[API] 로그인 오류: $e');
      return {'success': false, 'message': '서버 연결 오류'};
    }
  }

  // 대시보드 상태 조회
  Future<Map<String, dynamic>> getDashboardStatus() async {
    try {
      print('[API] getDashboardStatus 호출 - token: ${_token != null ? "있음" : "없음"}, username: $_username');
      
      if (_token == null) {
        print('[API] 오류: 토큰이 없습니다');
        return {'success': false, 'message': '인증 토큰이 없습니다'};
      }
      
      final response = await http.get(
        Uri.parse('$baseUrl/api/user/dashboard/status'),
        headers: {'Authorization': 'Bearer $_token'},
      ).timeout(const Duration(seconds: 10));

      print('[API] getDashboardStatus 응답: ${response.statusCode}');

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        print('[API] 상태 조회 실패: ${response.statusCode} - ${response.body}');
        return {'success': false, 'message': '상태 조회 실패 (${response.statusCode})'};
      }
    } catch (e) {
      print('[API] 네트워크 오류: $e');
      return {'success': false, 'message': '서버 연결 오류'};
    }
  }

  // FC 채굴량 조회
  Future<Map<String, dynamic>> getFCMining(String username, String period, {String? startDate, String? endDate}) async {
    try {
      String url = '$baseUrl/api/user/fc-mining?username=$username&period=$period';
      if (period == 'custom' && startDate != null && endDate != null) {
        url += '&start_date=$startDate&end_date=$endDate';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $_token'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {'success': false, 'message': 'FC 채굴량 조회 실패'};
      }
    } catch (e) {
      return {'success': false, 'message': '서버 연결 오류'};
    }
  }

  // 순위/점수 조회
  Future<Map<String, dynamic>> getRankScore(String username, String period, {String? startDate, String? endDate}) async {
    try {
      String url = '$baseUrl/api/user/rank-score?username=$username&period=$period';
      if (period == 'custom' && startDate != null && endDate != null) {
        url += '&start_date=$startDate&end_date=$endDate';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $_token'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {'success': false, 'message': '순위/점수 조회 실패'};
      }
    } catch (e) {
      return {'success': false, 'message': '서버 연결 오류'};
    }
  }

  // 일별 경기수 조회
  Future<Map<String, dynamic>> getMatchCount(String username, String period, String mode, {String? startDate, String? endDate}) async {
    try {
      String url = '$baseUrl/api/user/match-count?username=$username&period=$period&mode=$mode';
      if (period == 'custom' && startDate != null && endDate != null) {
        url += '&start_date=$startDate&end_date=$endDate';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $_token'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {'success': false, 'message': '경기수 조회 실패'};
      }
    } catch (e) {
      return {'success': false, 'message': '서버 연결 오류'};
    }
  }

  // 전적 조회
  Future<Map<String, dynamic>> getMatchHistory({
    required String username,
    String mode = 'manager_mode',
    String result = 'all',
    String period = '7',
    String? startDate,
    String? endDate,
  }) async {
    try {
      final params = {
        'username': username,
        'mode': mode,
        'result': result,
        'period': period,
        if (startDate != null) 'start_date': startDate,
        if (endDate != null) 'end_date': endDate,
      };
      
      final uri = Uri.parse('$baseUrl/api/user/match-history').replace(queryParameters: params);
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $_token'},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {'success': false, 'message': '전적 조회 실패'};
      }
    } catch (e) {
      return {'success': false, 'message': '서버 연결 오류'};
    }
  }

  // 매크로 제어 명령 전송
  Future<Map<String, dynamic>> sendControlCommand({
    required String username,
    required String action,
    String? mode,
    bool clubDonation = false,
    Map<String, dynamic>? parkingConditions,
  }) async {
    try {
      final requestBody = {
        'username': username,
        'action': action,
        if (mode != null) 'mode': mode,
        'club_donation': clubDonation,
        if (parkingConditions != null) 'parking_conditions': parkingConditions,
      };

      final response = await http.post(
        Uri.parse('$baseUrl/api/user/control/send'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json'
        },
        body: json.encode(requestBody),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final data = json.decode(response.body);
        return {'success': false, 'message': data['message'] ?? '제어 명령 전송 실패'};
      }
    } catch (e) {
      return {'success': false, 'message': '서버 연결 오류'};
    }
  }

  // 매크로 시작
  Future<Map<String, dynamic>> startMacro(String username, String mode, {bool clubDonation = false, Map<String, dynamic>? parkingConditions}) async {
    return sendControlCommand(
      username: username,
      action: 'start',
      mode: mode,
      clubDonation: clubDonation,
      parkingConditions: parkingConditions,
    );
  }

  // 매크로 중지
  Future<Map<String, dynamic>> stopMacro(String username) async {
    return sendControlCommand(
      username: username,
      action: 'stop',
    );
  }
  
  // 알림 목록 조회
  Future<Map<String, dynamic>> getNotifications({int limit = 30}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/v2/notifications?limit=$limit'),
        headers: {'Authorization': 'Bearer $_token'},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {'success': false, 'message': '알림 조회 실패'};
      }
    } catch (e) {
      return {'success': false, 'message': '서버 연결 오류'};
    }
  }
  
  Future<Map<String, dynamic>> logout() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/user/auth/logout'),
        headers: {'Authorization': 'Bearer $_token'},
      );

      // 모든 인증 정보 삭제 (SharedPreferences + 메모리 토큰)
      await clearAutoLogin();

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {'success': false, 'message': '로그아웃 실패'};
      }
    } catch (e) {
      return {'success': false, 'message': '서버 연결 오류'};
    }
  }
  
  // ===== 랭킹/컷라인 조회 API 제거됨 =====
  // Flutter 앱에서 직접 Nexon 웹페이지 크롤링하도록 변경

  // 시즌 D-day 조회
  Future<Map<String, dynamic>> getSeasonInfo() async {
    try {
      final uri = Uri.parse('$baseUrl/api/season_info');
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {'success': false};
    } catch (e) {
      return {'success': false};
    }
  }
}
