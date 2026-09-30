import '../constants/positions.dart';
import '../widgets/tc_picker.dart';
import 'ovr_formula.dart';

/// 선수 상세·비교 화면의 능력치 계산 (2026-09-30, '선수(집훈)' 탭).
///
/// 서버는 세부 능력 34종을 0강 기준 값으로 준다. 화면이 고른 강화·적응도·팀컬러를 더한다.
///   표시 값 = 0강 값 + 강화 상승값(kGradeBonus) + 적응도 상승값(kAdapBonus) + 팀컬러 전체 +N + 팀컬러 세부 효과
/// 집훈 계산기와 같은 식이며(집중훈련 가산만 없음), 넥슨 데이터센터 값과 대조 확인:
///   손흥민 TK 속력 0강 125 → 1강 128 → 8강 143, 적응도 Lv.5는 +4.
class PlayerCalc {
  PlayerCalc._();

  /// 6개 묶음 순서 (넥슨 화면 순서)
  static const faceOrder = ['스피드', '슛', '패스', '드리블', '수비', '피지컬'];

  /// 6개 묶음 가중치(%) — 가중합을 내림. 넥슨 비교 화면 실측과 12/12 일치(TK 1강·26TOTS 5강, 2026-09-30)
  static const faceWeights = <String, Map<String, int>>{
    '스피드': {'가속력': 45, '속력': 55},
    '슛': {'골 결정력': 45, '중거리 슛': 20, '슛 파워': 20, '페널티 킥': 5, '위치 선정': 5, '발리슛': 5},
    '패스': {'짧은 패스': 35, '시야': 20, '크로스': 20, '긴 패스': 15, '커브': 5, '프리킥': 5},
    '드리블': {'드리블': 50, '볼 컨트롤': 35, '민첩성': 10, '밸런스': 5},
    '수비': {'대인 수비': 30, '태클': 30, '가로채기': 20, '헤더': 10, '슬라이딩 태클': 10},
    '피지컬': {'몸싸움': 50, '스태미너': 25, '적극성': 20, '점프': 5},
  };

  /// 강화·적응도·팀컬러를 반영한 세부 능력치.
  static Map<String, num> effStats(
    Map<String, int> base, {
    int grade = 1,
    int adap = 1,
    Iterable<TcPick> picks = const [],
  }) {
    var all = (kGradeBonus[grade] ?? 0) + (kAdapBonus[adap] ?? 0);
    final detail = <String, int>{};
    for (final p in picks) {
      all += p.all;
      p.detail.forEach((k, v) => detail[k] = (detail[k] ?? 0) + v);
    }
    return {for (final e in base.entries) e.key: e.value + all + (detail[e.key] ?? 0)};
  }

  /// 총 능력치 (세부 능력 34종 합)
  static int totalStats(Map<String, num> eff) {
    num sum = 0;
    for (final k in OvrFormula.statKeys) {
      sum += eff[k] ?? 0;
    }
    return sum.round();
  }

  /// 6개 묶음 값
  static Map<String, int> faceStats(Map<String, num> eff) {
    final out = <String, int>{};
    for (final name in faceOrder) {
      var sum = 0.0;
      faceWeights[name]!.forEach((k, w) => sum += (eff[k] ?? 0) * w);
      out[name] = (sum / 100 + 1e-9).floor();
    }
    return out;
  }

  /// 포지션 OVR (집훈 계산기와 같은 공식)
  static int ovr(Map<String, num> eff, String position) => OvrFormula.calc(eff, position);

  /// 비교 팝업의 차이 숫자 — 높은 쪽에만 차이를 준다
  static ({int left, int right}) diff(num a, num b) {
    final d = (a - b).round();
    return (left: d > 0 ? d : 0, right: d < 0 ? -d : 0);
  }

  /// 강화 단계별 시세 문자열('0|1강|2강|…')에서 [grade]강 값. 없으면 null.
  static int? priceAt(String? eachPrice, int grade) {
    if (eachPrice == null || eachPrice.isEmpty) return null;
    final parts = eachPrice.split('|');
    if (grade < 0 || grade >= parts.length) return null;
    final digits = parts[grade].replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    final v = int.tryParse(digits);
    return (v == null || v <= 0) ? null : v;
  }

  /// 검색 목록 줄의 포지션별 OVR(서버 값은 0강 기준)을 [grade]강 값으로.
  static List<({String pos, int ovr})> shownPositions(List<dynamic>? positions, int grade) {
    final bonus = kGradeBonus[grade] ?? 0;
    final out = <({String pos, int ovr})>[];
    for (final p in positions ?? const []) {
      if (p is! Map) continue;
      final ovr = (p['ovr'] as num?)?.toInt();
      if (ovr == null) continue;
      out.add((pos: '${p['pos'] ?? ''}'.toUpperCase(), ovr: ovr + bonus));
    }
    return out;
  }
}
