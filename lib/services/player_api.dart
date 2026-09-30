import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/player_query.dart';
import 'api_service.dart';

/// '선수(집훈)' 탭 서버 호출 (2026-09-30).
///
/// - 검색: `/api/user/player/search` — players[].positions의 OVR은 0강 기준
/// - 조건 목록: `/api/user/player/search-options` (앱 실행 중 1회만 받아 보관)
/// - 상세·비교: `/api/user/player/detail?spids=a,b`
/// - 시세 그래프: `/api/user/player/price-history?spid=&grade=`
class PlayerApi {
  PlayerApi._();

  static Map<String, dynamic>? _options;
  static Future<Map<String, dynamic>?>? _optionsLoading;

  static Future<Map<String, dynamic>> _get(String path, Map<String, String> params, {int timeoutSec = 30}) async {
    final uri = Uri.parse('${ApiService.baseUrl}$path').replace(queryParameters: params.isEmpty ? null : params);
    final r = await http.get(uri).timeout(Duration(seconds: timeoutSec));
    final d = json.decode(r.body);
    return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{'success': false};
  }

  /// 검색. 실패 시 {'success': false, 'message': …}.
  static Future<Map<String, dynamic>> search(PlayerQuery q) => _get('/api/user/player/search', q.toParams());

  /// 조건 목록 (시즌·리그·클럽·국적·특성 등). 실패 시 null — 다음 호출에서 다시 시도한다.
  static Future<Map<String, dynamic>?> options() {
    if (_options != null) return Future.value(_options);
    return _optionsLoading ??= _loadOptions();
  }

  static Future<Map<String, dynamic>?> _loadOptions() async {
    try {
      final d = await _get('/api/user/player/search-options', const {}, timeoutSec: 40);
      if (d['success'] == true) _options = d;
    } catch (e) {
      print('[PlayerApi] 조건 목록 실패: $e');
    } finally {
      _optionsLoading = null;
    }
    return _options;
  }

  /// 특성 이름 → 아이콘 주소 (조건 목록을 받은 뒤에만 값이 있다)
  static String? traitIcon(String name) {
    for (final t in (_options?['traits'] as List? ?? const [])) {
      if (t is Map && t['name'] == name) return t['icon']?.toString();
    }
    return null;
  }

  /// 상세·비교용 카드 정보. 반환: spid → 카드 정보 (실패한 카드는 빠짐)
  static Future<Map<int, Map<String, dynamic>>> detail(List<int> spids) async {
    final d = await _get('/api/user/player/detail', {'spids': spids.join(',')});
    if (d['success'] != true) throw Exception(d['message'] ?? '세부 능력치를 가져오지 못했습니다.');
    final out = <int, Map<String, dynamic>>{};
    (d['players'] as Map? ?? {}).forEach((k, v) {
      final id = int.tryParse('$k');
      if (id != null && v is Map) out[id] = Map<String, dynamic>.from(v);
    });
    return out;
  }

  /// 카드가 고를 수 있는 팀컬러 목록 (강화·소속·특성) — 집훈 계산기와 같은 주소
  static Future<Map<String, List<Map<String, dynamic>>>> cardTeamcolors(int spid) async {
    final d = await _get('/api/user/squad/card-teamcolors', {'spid': '$spid'}, timeoutSec: 20);
    final out = <String, List<Map<String, dynamic>>>{'enhance': [], 'affiliation': [], 'feature': []};
    if (d['success'] != true) return out;
    (d['options'] as Map? ?? {}).forEach((k, v) {
      out['$k'] = (v as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    });
    return out;
  }

  static List<Map<String, dynamic>>? _teamcolors;

  /// 팀컬러 목록 [{tc_id, name, kind}] (조건 시트의 팀컬러 고르기용, 앱 실행 중 1회만 받는다)
  static Future<List<Map<String, dynamic>>> teamcolors() async {
    if (_teamcolors != null) return _teamcolors!;
    try {
      final d = await _get('/api/user/squad/teamcolors', const {}, timeoutSec: 25);
      if (d['success'] == true) {
        _teamcolors = [
          for (final t in (d['teamcolors'] as List? ?? const []))
            if (t is Map) {'id': t['tc_id'], 'name': '${t['name'] ?? ''}', 'kind': '${t['kind'] ?? ''}'}
        ];
      }
    } catch (e) {
      print('[PlayerApi] 팀컬러 목록 실패: $e');
    }
    return _teamcolors ?? const [];
  }

  /// 일별 시세: {current, times[], values[]} — 실패 시 null
  static Future<Map<String, dynamic>?> priceHistory(int spid, int grade) async {
    try {
      final d = await _get('/api/user/player/price-history', {'spid': '$spid', 'grade': '$grade'});
      return d['success'] == true ? d : null;
    } catch (e) {
      print('[PlayerApi] 시세 그래프 실패: $e');
      return null;
    }
  }
}
