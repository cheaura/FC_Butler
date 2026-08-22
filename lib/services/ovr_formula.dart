import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

/// FC 온라인 포지션별 OVR 공식 (집중훈련 계산기) — 서버 utils/ovr_formula.py와 동일.
///
/// 검증(2026-08-22): 407장×28포지션 11,396건 eachOvr 100% 일치 + 넥슨 n1Grow 오라클 30/30.
/// 규칙: OVR = floor(Σ 세부스탯 × 가중치 / 100). 강화·집중훈련·팀컬러 '전체 능력치'는 전 스탯 균등 가산.
/// 내장 표는 폴백이며, 서버 `/api/user/squad/ovr-weights`의 version이 다르면 갱신해 저장한다.
class OvrFormula {
  OvrFormula._();

  static const builtinVersion = '2026-08-22.1';
  static const positions = ['gk', 'sw', 'rwb', 'rb', 'rcb', 'cb', 'lcb', 'lb', 'lwb', 'rdm', 'cdm', 'ldm', 'rm', 'rcm', 'cm', 'lcm', 'lm', 'ram', 'cam', 'lam', 'rf', 'cf', 'lf', 'rw', 'rs', 'st', 'ls', 'lw'];
  static const statKeys = ['속력', '가속력', '골 결정력', '슛 파워', '중거리 슛', '위치 선정', '발리슛', '페널티 킥', '짧은 패스', '시야', '크로스', '긴 패스', '프리킥', '커브', '드리블', '볼 컨트롤', '민첩성', '밸런스', '반응 속도', '대인 수비', '태클', '가로채기', '헤더', '슬라이딩 태클', '몸싸움', '스태미너', '적극성', '점프', '침착성', 'GK 다이빙', 'GK 핸들링', 'GK 킥', 'GK 반응속도', 'GK 위치 선정'];
  static const positionGroup = {
    'gk': 'GK',
    'sw': 'SW',
    'rwb': 'WB',
    'lwb': 'WB',
    'rb': 'B',
    'lb': 'B',
    'rcb': 'CB',
    'cb': 'CB',
    'lcb': 'CB',
    'rdm': 'CDM',
    'cdm': 'CDM',
    'ldm': 'CDM',
    'rm': 'M',
    'lm': 'M',
    'rcm': 'CM',
    'cm': 'CM',
    'lcm': 'CM',
    'ram': 'CAM',
    'cam': 'CAM',
    'lam': 'CAM',
    'rf': 'CF',
    'cf': 'CF',
    'lf': 'CF',
    'rw': 'W',
    'lw': 'W',
    'rs': 'ST',
    'st': 'ST',
    'ls': 'ST',
  };
  static const builtinWeights = <String, Map<String, int>>{
    'ST': {
      '골 결정력': 18,
      '위치 선정': 13,
      '볼 컨트롤': 10,
      '슛 파워': 10,
      '헤더': 10,
      '반응 속도': 8,
      '드리블': 7,
      '몸싸움': 5,
      '속력': 5,
      '짧은 패스': 5,
      '가속력': 4,
      '중거리 슛': 3,
      '발리슛': 2,
    },
    'CF': {
      '볼 컨트롤': 15,
      '드리블': 14,
      '위치 선정': 13,
      '골 결정력': 11,
      '반응 속도': 9,
      '짧은 패스': 9,
      '시야': 8,
      '슛 파워': 5,
      '속력': 5,
      '가속력': 5,
      '중거리 슛': 4,
      '헤더': 2,
    },
    'W': {
      '드리블': 16,
      '볼 컨트롤': 14,
      '골 결정력': 10,
      '위치 선정': 9,
      '짧은 패스': 9,
      '크로스': 9,
      '반응 속도': 7,
      '가속력': 7,
      '시야': 6,
      '속력': 6,
      '중거리 슛': 4,
      '민첩성': 3,
    },
    'CAM': {
      '짧은 패스': 16,
      '볼 컨트롤': 15,
      '시야': 14,
      '드리블': 13,
      '위치 선정': 9,
      '반응 속도': 7,
      '골 결정력': 7,
      '중거리 슛': 5,
      '가속력': 4,
      '긴 패스': 4,
      '속력': 3,
      '민첩성': 3,
    },
    'CM': {
      '짧은 패스': 17,
      '볼 컨트롤': 14,
      '시야': 13,
      '긴 패스': 13,
      '반응 속도': 8,
      '드리블': 7,
      '위치 선정': 6,
      '스태미너': 6,
      '가로채기': 5,
      '태클': 5,
      '중거리 슛': 4,
      '골 결정력': 2,
    },
    'M': {
      '드리블': 15,
      '볼 컨트롤': 13,
      '짧은 패스': 11,
      '크로스': 10,
      '위치 선정': 8,
      '반응 속도': 7,
      '가속력': 7,
      '시야': 7,
      '골 결정력': 6,
      '속력': 6,
      '스태미너': 5,
      '긴 패스': 5,
    },
    'CDM': {
      '짧은 패스': 14,
      '가로채기': 14,
      '태클': 12,
      '볼 컨트롤': 10,
      '긴 패스': 10,
      '대인 수비': 9,
      '반응 속도': 7,
      '스태미너': 6,
      '적극성': 5,
      '슬라이딩 태클': 5,
      '시야': 4,
      '몸싸움': 4,
    },
    'CB': {
      '태클': 17,
      '대인 수비': 14,
      '가로채기': 13,
      '슬라이딩 태클': 10,
      '헤더': 10,
      '몸싸움': 10,
      '적극성': 7,
      '반응 속도': 5,
      '짧은 패스': 5,
      '볼 컨트롤': 4,
      '점프': 3,
      '속력': 2,
    },
    'SW': {
      '대인 수비': 15,
      '태클': 15,
      '슬라이딩 태클': 15,
      '헤더': 10,
      '몸싸움': 10,
      '가로채기': 8,
      '적극성': 8,
      '반응 속도': 5,
      '볼 컨트롤': 5,
      '짧은 패스': 5,
      '점프': 4,
    },
    'B': {
      '슬라이딩 태클': 14,
      '가로채기': 12,
      '태클': 11,
      '크로스': 9,
      '스태미너': 8,
      '반응 속도': 8,
      '대인 수비': 8,
      '볼 컨트롤': 7,
      '짧은 패스': 7,
      '속력': 7,
      '가속력': 5,
      '헤더': 4,
    },
    'WB': {
      '가로채기': 12,
      '크로스': 12,
      '슬라이딩 태클': 11,
      '짧은 패스': 10,
      '스태미너': 10,
      '태클': 8,
      '볼 컨트롤': 8,
      '반응 속도': 8,
      '대인 수비': 7,
      '속력': 6,
      '드리블': 4,
      '가속력': 4,
    },
    'GK': {
      'GK 다이빙': 21,
      'GK 핸들링': 21,
      'GK 위치 선정': 21,
      'GK 반응속도': 21,
      '반응 속도': 11,
      'GK 킥': 5,
    },
  };

  static String version = builtinVersion;
  static Map<String, Map<String, int>> weights = builtinWeights;
  static Map<String, String> groups = positionGroup;
  static bool _loaded = false;

  /// 저장된 최신 표 로드 후 서버 버전 확인 (실패해도 내장 표로 동작)
  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('ovr_weights_v1');
      if (saved != null) _apply(json.decode(saved));
    } catch (_) {}
    try {
      final r = await http
          .get(Uri.parse('${ApiService.baseUrl}/api/user/squad/ovr-weights?version=$version'))
          .timeout(const Duration(seconds: 10));
      final d = json.decode(r.body);
      if (d['success'] == true && d['not_modified'] != true && d['weights'] != null) {
        _apply(d);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('ovr_weights_v1', json.encode(d));
      }
    } catch (_) {}
  }

  static void _apply(dynamic d) {
    if (d is! Map) return;
    final w = <String, Map<String, int>>{};
    (d['weights'] as Map? ?? {}).forEach((g, m) {
      w['$g'] = {for (final e in (m as Map).entries) '${e.key}': (e.value as num).toInt()};
    });
    if (w.isEmpty) return;
    weights = w;
    groups = {
      for (final e in (d['position_group'] as Map? ?? positionGroup).entries)
        '${e.key}': '${e.value}'
    };
    version = '${d['version'] ?? version}';
  }

  /// 가중합/100 (내림 전 실수값)
  static double weightedSum(Map<String, num> stats, String position) {
    final g = groups[position.toLowerCase()];
    final w = g == null ? null : weights[g];
    if (w == null) return 0;
    var sum = 0.0;
    w.forEach((k, v) => sum += (stats[k] ?? 0) * v);
    return sum / 100.0;
  }

  /// 포지션 OVR (내림)
  static int calc(Map<String, num> stats, String position) =>
      (weightedSum(stats, position) + 1e-9).floor();

  /// 해당 포지션에서 가중치 있는 스탯 목록 (가중치 내림차순)
  static List<MapEntry<String, int>> weightsFor(String position) {
    final g = groups[position.toLowerCase()];
    final w = g == null ? null : weights[g];
    if (w == null) return const [];
    return w.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }
}
