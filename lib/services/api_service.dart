import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'fcm_service.dart';

class ApiService {
  // 싱글톤 패턴
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();
  
  static const String baseUrl = 'https://api.panenka9.com';
  String? _token;
  String? _username;
  String? _accountType; // 'macro'=매크로 연동(전체 탭) / 'public'=공개 가입(조회만)

  // Token getter
  String? get token => _token;
  String? get username => _username;
  String? get accountType => _accountType;
  bool get isMacroAccount => _accountType == 'macro';
  bool get isLoggedIn => _token != null;

  // ===== 자동로그인 체크 (앱 시작 시 호출) =====
  // 검증은 /api/user/auth/verify 사용 — 계정 유형을 함께 받고,
  // 서버가 장기 세션을 슬라이딩 연장하므로 계속 쓰면 로그인이 풀리지 않는다.
  Future<Map<String, dynamic>> checkAutoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getString('auth_token');
      final savedUsername = prefs.getString('username');
      final expiryTime = prefs.getInt('token_expiry');

      if (savedToken != null && savedUsername != null && expiryTime != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now < expiryTime) {
          _token = savedToken;
          _username = savedUsername;

          final response = await http.post(
            Uri.parse('$baseUrl/api/user/auth/verify'),
            headers: {'Authorization': 'Bearer $_token'},
          ).timeout(Duration(seconds: 5));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            if (data['valid'] == true) {
              _accountType = data['account_type'] ?? prefs.getString('account_type') ?? 'macro';
              await prefs.setString('account_type', _accountType!);
              // 로컬 만료 시각도 갱신 (서버 세션이 연장되므로 30일 재연장)
              await prefs.setInt('token_expiry',
                  DateTime.now().add(Duration(days: 30)).millisecondsSinceEpoch);
              return {
                'success': true,
                'username': savedUsername,
                'account_type': _accountType,
              };
            }
          }
        }
      }

      // 자동로그인 실패 - 저장된 정보 삭제
      await clearAutoLogin();
      return {'success': false};

    } catch (e) {
      print('[자동로그인 체크 오류] $e');
      // 네트워크 일시 오류로 저장된 로그인을 지우지 않도록: 로컬 만료 내라면 보류
      return {'success': false, 'network_error': true};
    }
  }

  // ===== 자동로그인 정보 저장 =====
  Future<void> saveAutoLogin(String token, String username, [String? accountType]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final expiryTime = DateTime.now().add(Duration(days: 30)).millisecondsSinceEpoch;

      await prefs.setString('auth_token', token);
      await prefs.setString('username', username);
      await prefs.setInt('token_expiry', expiryTime);
      if (accountType != null) {
        await prefs.setString('account_type', accountType);
      }

      _token = token;
      _username = username;
      if (accountType != null) _accountType = accountType;

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
      await prefs.remove('account_type');

      // 로그아웃이므로 메모리 토큰도 삭제
      _token = null;
      _username = null;
      _accountType = null;

      print('[로그아웃] 모든 인증 정보 삭제 완료');
    } catch (e) {
      print('[자동로그인 삭제 오류] $e');
    }
  }

  // ===== 공개 회원가입 (즉시 활성 — 조회 계정) =====
  Future<Map<String, dynamic>> register(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/user/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'password': password,
          'agree_terms': true, // 가입 화면에서 동의 체크 후에만 호출됨
        }),
      ).timeout(Duration(seconds: 10));

      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        _token = data['token'];
        _username = data['username'];
        _accountType = data['account_type'] ?? 'public';
        await saveAutoLogin(_token!, _username!, _accountType);
        return {'success': true, 'username': _username, 'account_type': _accountType};
      }
      return {'success': false, 'message': data['message'] ?? '가입에 실패했습니다.'};
    } catch (e) {
      print('[API] 회원가입 오류: $e');
      return {'success': false, 'message': '서버 연결 오류'};
    }
  }

  // ===== 인앱 계정 삭제 (탈퇴 — 스토어 정책 의무) =====
  Future<Map<String, dynamic>> deleteAccount(String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/user/auth/delete-account'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: json.encode({'password': password}),
      ).timeout(Duration(seconds: 10));

      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        await clearAutoLogin();
        return {'success': true};
      }
      return {'success': false, 'message': data['message'] ?? '계정 삭제에 실패했습니다.'};
    } catch (e) {
      print('[API] 계정 삭제 오류: $e');
      return {'success': false, 'message': '서버 연결 오류'};
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
        _accountType = data['account_type'] ?? 'macro';
        print('[API] 토큰 설정 완료: ${_token != null ? "있음" : "없음"}, username: $_username, type: $_accountType');

        // 자동로그인 체크 시에만 SharedPreferences에 저장
        if (rememberMe) {
          await saveAutoLogin(data['token'], username, _accountType);
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

        return {'success': true, 'username': username, 'account_type': _accountType};
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
    String season = 'all', // 시즌 필터 (all / 넥슨 시즌 번호 / none) — 2026-09-05
  }) async {
    try {
      final params = {
        'username': username,
        'mode': mode,
        'result': result,
        'period': period,
        if (startDate != null) 'start_date': startDate,
        if (endDate != null) 'end_date': endDate,
        if (season != 'all') 'season': season,
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
    bool? clubDonation, // null=미전송 (1.8.1+ 클라는 PC 설정 유지 — 'PC 설정 제어'로 일원화)
    Map<String, dynamic>? parkingConditions,
    Map<String, dynamic>? extra, // 확장 파라미터 (games/shutdown/hour/minute/enabled 등)
  }) async {
    try {
      final requestBody = {
        'username': username,
        'action': action,
        if (mode != null) 'mode': mode,
        if (clubDonation != null) 'club_donation': clubDonation,
        if (parkingConditions != null) 'parking_conditions': parkingConditions,
        if (extra != null) ...extra,
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

  // 매크로 시작 (leagueSub: 'manager'|'ai', bgMode/clubDonation: null=PC 설정 유지)
  Future<Map<String, dynamic>> startMacro(String username, String mode,
      {bool? clubDonation,
      Map<String, dynamic>? parkingConditions,
      String? leagueSub,
      bool? bgMode}) async {
    return sendControlCommand(
      username: username,
      action: 'start',
      mode: mode,
      clubDonation: clubDonation,
      parkingConditions: parkingConditions,
      extra: {
        if (leagueSub != null) 'league_sub': leagueSub,
        if (bgMode != null) 'bg_mode': bgMode,
      },
    );
  }

  // 매크로 중지
  Future<Map<String, dynamic>> stopMacro(String username) async {
    return sendControlCommand(
      username: username,
      action: 'stop',
    );
  }

  // 일시정지 / 재개
  Future<Map<String, dynamic>> pauseMacro(String username) =>
      sendControlCommand(username: username, action: 'pause');

  Future<Map<String, dynamic>> resumeMacro(String username) =>
      sendControlCommand(username: username, action: 'resume');

  // 예약 정지: N경기 후 정지 (+컴퓨터 종료)
  Future<Map<String, dynamic>> reserveStop(String username, int games, bool shutdown) =>
      sendControlCommand(username: username, action: 'reserve_stop',
          extra: {'games': games, 'shutdown': shutdown});

  Future<Map<String, dynamic>> cancelReserveStop(String username) =>
      sendControlCommand(username: username, action: 'cancel_reserve_stop');

  // 예약 정지: 시각 지정 (+컴퓨터 종료)
  Future<Map<String, dynamic>> reserveStopTime(String username, int hour, int minute, bool shutdown) =>
      sendControlCommand(username: username, action: 'reserve_stop_time',
          extra: {'hour': hour, 'minute': minute, 'shutdown': shutdown});

  Future<Map<String, dynamic>> cancelReserveStopTime(String username) =>
      sendControlCommand(username: username, action: 'cancel_reserve_stop_time');

  // 자동재시작 on/off
  Future<Map<String, dynamic>> setAutoRestart(String username, bool enabled) =>
      sendControlCommand(username: username, action: 'set_auto_restart',
          extra: {'enabled': enabled});

  // 전술/기능 토글 (rage_mode/offside_trap/team_press/relegation_defense/club_donation 중 일부)
  Future<Map<String, dynamic>> setToggles(String username, Map<String, bool> toggles) =>
      sendControlCommand(username: username, action: 'set_toggles', extra: toggles);
  
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

  // 연동 계정 목록 (탭 내 계정 선택기용)
  Future<Map<String, dynamic>> getLinkedAccounts() async {
    return _authGet('/api/user/linked-accounts/list', timeoutSec: 10);
  }

  // ===== 이적시장 거래기록 (2026-07-14, 웹 대시보드와 동일 API) =====

  // 공통 GET 헬퍼
  Future<Map<String, dynamic>> _authGet(String path, {int timeoutSec = 20}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl$path'),
        headers: {'Authorization': 'Bearer $_token'},
      ).timeout(Duration(seconds: timeoutSec));
      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'error': '서버 연결 오류'};
    }
  }

  // 넥슨 API 키 등록 상태
  Future<Map<String, dynamic>> getNexonKeyStatus(String username) async {
    return _authGet('/api/user/nexon-key/status?username=${Uri.encodeComponent(username)}');
  }

  // 넥슨 API 키 등록
  Future<Map<String, dynamic>> registerNexonKey(String username, String apiKey) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/user/nexon-key'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'username': username, 'api_key': apiKey}),
      ).timeout(const Duration(seconds: 20));
      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'error': '서버 연결 오류'};
    }
  }

  // 넥슨 API 키 삭제
  Future<Map<String, dynamic>> deleteNexonKey(String username) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/user/nexon-key?username=${Uri.encodeComponent(username)}'),
        headers: {'Authorization': 'Bearer $_token'},
      ).timeout(const Duration(seconds: 15));
      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'error': '서버 연결 오류'};
    }
  }

  // 거래내역 조회 (type: buy/sell/all, 페이지네이션)
  Future<Map<String, dynamic>> getTradeHistory({
    required String username,
    String type = 'all',
    String player = '',
    String season = '',
    int offset = 0,
    int limit = 30,
  }) async {
    final params = <String, String>{
      'username': username,
      'type': type,
      'offset': '$offset',
      'limit': '$limit',
      if (player.isNotEmpty) 'player': player,
      if (season.isNotEmpty) 'season': season,
    };
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return _authGet('/api/user/market/trade-history?$query', timeoutSec: 30);
  }

  // 내 스쿼드 손익
  Future<Map<String, dynamic>> getSquadPnl(String username) async {
    return _authGet(
        '/api/user/market/squad-pnl?username=${Uri.encodeComponent(username)}&mode=manager_mode',
        timeoutSec: 30);
  }

  // ===== 전적 분석 리포트 (2026-07-14, 웹 대시보드와 동일 API) =====

  // 분석 시작 (캐시 적중 시 status='done' + result 즉시 반환)
  Future<Map<String, dynamic>> startMatchAnalysis(
      String username, Map<String, dynamic> scope) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/user/match-analysis/start'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'username': username, 'scope': scope}),
      ).timeout(const Duration(seconds: 20));
      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'error': '서버 연결 오류'};
    }
  }

  // 분석 상태 폴링
  Future<Map<String, dynamic>> getAnalysisStatus(String jobId) async {
    return _authGet('/api/user/match-analysis/status?job_id=$jobId', timeoutSec: 10);
  }

  // 분석 결과
  Future<Map<String, dynamic>> getAnalysisResult(String jobId) async {
    return _authGet('/api/user/match-analysis/result?job_id=$jobId', timeoutSec: 20);
  }

  // 최근 분석 결과 (지난 분석 열기)
  Future<Map<String, dynamic>> getLatestAnalysis(String username) async {
    return _authGet(
        '/api/user/match-analysis/latest?username=${Uri.encodeComponent(username)}',
        timeoutSec: 15);
  }

  // 시간대별 승률 (2026-07-25, 웹 대시보드와 동일 API — 전체/최근30일/최근15일 × 24시간)
  Future<Map<String, dynamic>> getHourlyWinrate(String username) async {
    return _authGet(
        '/api/user/hourly-winrate?username=${Uri.encodeComponent(username)}',
        timeoutSec: 15);
  }

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
