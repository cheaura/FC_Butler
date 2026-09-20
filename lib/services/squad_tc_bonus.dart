import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/positions.dart';
import 'api_service.dart';

/// 선발 명단의 팀컬러 '전체 능력치' 보너스 (2026-09-20).
///
/// 스쿼드 탭은 넥슨 팀컬러 계산기(`/api/user/squad/teamcolor`) 결과를 OVR에 더하는데,
/// 검색 탭 선발 스쿼드·경기 상세는 기본+강화+적응도만 더해 같은 스쿼드가 8~9 낮게 보이던 문제 수정용.
/// 계산식은 스쿼드 탭 `_ovrAt`과 동일: 소속/강화 보너스(tc_base_bonus_by_spid) + 넥슨 기본 배정 특성 팀컬러(ovr_bonus).
///
/// 실패 응답은 캐시하지 않는다 (화면은 팀컬러 미반영 값으로 유지).
class SquadTcBonus {
  SquadTcBonus._();

  static final Map<String, Map<int, int>> _cache = {}; // 구성 키 → {spid: 보너스}
  static final Map<String, Future<Map<int, int>?>> _pending = {};

  /// 구성 키: 선수별 spid·강화·포지션 (포메이션은 넥슨 계산 결과에 영향 없음 — 실측)
  static String _keyOf(List<SquadTcPlayer> players) {
    final parts = players.map((p) => '${p.spid}:${p.grade}:${p.spPos}').toList()..sort();
    return parts.join('|');
  }

  /// 이미 계산된 보너스 (없으면 null). 위젯 build에서 동기 접근용.
  static Map<int, int>? cached(List<SquadTcPlayer> players) => players.isEmpty ? null : _cache[_keyOf(players)];

  /// 보너스 확보 (서버 1회 호출, 같은 구성의 동시 요청은 하나로 합침). 실패하면 null.
  static Future<Map<int, int>?> ensure(List<SquadTcPlayer> players, {String? formation}) {
    if (players.isEmpty) return Future.value(null);
    final key = _keyOf(players);
    final hit = _cache[key];
    if (hit != null) return Future.value(hit);
    final running = _pending[key];
    if (running != null) return running;
    final f = _fetch(key, players, formation).whenComplete(() => _pending.remove(key));
    _pending[key] = f;
    return f;
  }

  static Future<Map<int, int>?> _fetch(String key, List<SquadTcPlayer> players, String? formation) async {
    try {
      final r = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/api/user/squad/teamcolor'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'formation': (formation ?? '').isNotEmpty ? formation : '4-1-2-3',
              'adap': 5,
              'players': [
                for (final p in players)
                  {
                    'spid': p.spid,
                    'grade': p.grade,
                    'role': kSpposRole[p.spPos] ?? 'cm',
                    'sp_position': p.spPos,
                    // 서버 메타 캐시 미스 시 재검색용 (스쿼드 탭과 동일)
                    'player_name': p.name,
                  },
              ],
            }),
          )
          .timeout(const Duration(seconds: 40));
      final d = json.decode(r.body);
      if (r.statusCode != 200 || d['success'] != true) return null;
      final out = <int, int>{};
      final baseMap = d['tc_base_bonus_by_spid'] as Map?;
      if (baseMap != null) {
        baseMap.forEach((k, v) {
          final spid = int.tryParse('$k');
          if (spid != null && v is num) out[spid] = (out[spid] ?? 0) + v.toInt();
        });
        // 특성 팀컬러: 넥슨 기본 배정(selected) 선수에게만 '전체 능력치' 가산
        for (final f in ((d['feature'] as Map?)?['active'] as List? ?? const [])) {
          if (f is! Map) continue;
          final bonus = (f['ovr_bonus'] as num?)?.toInt() ?? 0;
          if (bonus == 0) continue;
          for (final sp in (f['selected'] as List? ?? const [])) {
            final spid = int.tryParse('$sp');
            if (spid != null) out[spid] = (out[spid] ?? 0) + bonus;
          }
        }
      } else {
        // 구 서버 응답 폴백
        (d['tc_bonus_by_spid'] as Map? ?? const {}).forEach((k, v) {
          final spid = int.tryParse('$k');
          if (spid != null && v is num) out[spid] = v.toInt();
        });
      }
      _cache[key] = out;
      return out;
    } catch (e) {
      print('[SquadTcBonus] 팀컬러 계산 실패: $e');
      return null;
    }
  }
}

/// 팀컬러 계산 입력 1명 (선발 11명만 넘길 것 — 교체 명단 제외)
class SquadTcPlayer {
  final int spid;
  final int grade;
  final int spPos;
  final String name;
  const SquadTcPlayer({required this.spid, required this.grade, required this.spPos, this.name = ''});
}
