// 선수 상세·비교 계산 테스트 (2026-09-30) — 넥슨 데이터센터 실측 값과 대조.
// 기준 자료: 손흥민 TK(864200104) 1강, 손흥민 26TOTS(866200104) 5강 — 공식 비교 화면(PlayerVs) 응답.
// 실행: flutter test test/player_calc_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'package:fc_macro_app/services/player_calc.dart';
import 'package:fc_macro_app/widgets/tc_picker.dart';

const _keys = [
  '속력', '가속력', '골 결정력', '슛 파워', '중거리 슛', '위치 선정', '발리슛', '페널티 킥', '짧은 패스', '시야',
  '크로스', '긴 패스', '프리킥', '커브', '드리블', '볼 컨트롤', '민첩성', '밸런스', '반응 속도', '대인 수비',
  '태클', '가로채기', '헤더', '슬라이딩 태클', '몸싸움', '스태미너', '적극성', '점프', '침착성',
  'GK 다이빙', 'GK 핸들링', 'GK 킥', 'GK 반응속도', 'GK 위치 선정',
];

// 공식 화면 값: TK 1강 / 26TOTS 5강 (위 순서)
const _tk1 = [128, 128, 126, 127, 126, 130, 124, 111, 118, 116, 121, 103, 120, 128, 122, 118, 121, 120, 125, 71, 71, 67, 101, 66, 112, 125, 105, 100, 121, 24, 26, 25, 24, 22];
const _tots5 = [132, 132, 125, 131, 129, 135, 126, 116, 127, 129, 124, 109, 129, 133, 127, 123, 124, 124, 130, 75, 73, 71, 105, 70, 117, 126, 104, 104, 129, 24, 25, 25, 29, 28];

/// 0강 기준 값 (서버가 주는 형식) — 공식 값에서 강화 상승값(1강 3, 5강 9)을 뺀다
Map<String, int> _base(List<int> shown, int bonus) => {for (var i = 0; i < _keys.length; i++) _keys[i]: shown[i] - bonus};

void main() {
  final tk = _base(_tk1, 3);
  final tots = _base(_tots5, 9);

  group('PlayerCalc.effStats', () {
    test('1강·적응도 1: 0강 값 + 3', () {
      final eff = PlayerCalc.effStats(tk, grade: 1, adap: 1);
      expect(eff['속력'], 128);
      expect(eff['GK 위치 선정'], 22);
    });
    test('넥슨 실측: 8강 143, 8강+적응도 5 → 147(+4)', () {
      expect(PlayerCalc.effStats(tk, grade: 8, adap: 1)['속력'], 143);
      expect(PlayerCalc.effStats(tk, grade: 8, adap: 5)['속력'], 147);
    });
    test('팀컬러: 전체 +N은 모든 능력치, 세부 효과는 해당 능력치만', () {
      const pick = TcPick('affiliation', 1, '토트넘 홋스퍼', 1, 3, 2, {'시야': 3});
      final eff = PlayerCalc.effStats(tk, grade: 1, adap: 1, picks: const [pick]);
      expect(eff['속력'], 130);
      expect(eff['시야'], 116 + 2 + 3);
    });
  });

  group('PlayerCalc.faceStats (넥슨 6개 묶음)', () {
    test('TK 1강: 128 / 125 / 116 / 120 / 72 / 113', () {
      final f = PlayerCalc.faceStats(PlayerCalc.effStats(tk, grade: 1, adap: 1));
      expect([f['스피드'], f['슛'], f['패스'], f['드리블'], f['수비'], f['피지컬']], [128, 125, 116, 120, 72, 113]);
    });
    test('26TOTS 5강: 132 / 127 / 124 / 125 / 76 / 116', () {
      final f = PlayerCalc.faceStats(PlayerCalc.effStats(tots, grade: 5, adap: 1));
      expect([f['스피드'], f['슛'], f['패스'], f['드리블'], f['수비'], f['피지컬']], [132, 127, 124, 125, 76, 116]);
    });
    test('묶음 순서는 넥슨 화면 순서', () {
      expect(PlayerCalc.faceOrder, ['스피드', '슛', '패스', '드리블', '수비', '피지컬']);
    });
  });

  group('총 능력치·포지션 OVR', () {
    test('총 능력치: TK 1강 3372, 26TOTS 5강 3510', () {
      expect(PlayerCalc.totalStats(PlayerCalc.effStats(tk, grade: 1, adap: 1)), 3372);
      expect(PlayerCalc.totalStats(PlayerCalc.effStats(tots, grade: 5, adap: 1)), 3510);
    });
    test('포지션 OVR: TK 1강 ST 122·LW 122, 26TOTS 5강 CF 127·ST 125·CAM 127', () {
      final a = PlayerCalc.effStats(tk, grade: 1, adap: 1);
      expect(PlayerCalc.ovr(a, 'st'), 122);
      expect(PlayerCalc.ovr(a, 'lw'), 122);
      final b = PlayerCalc.effStats(tots, grade: 5, adap: 1);
      expect(PlayerCalc.ovr(b, 'cf'), 127);
      expect(PlayerCalc.ovr(b, 'st'), 125);
      expect(PlayerCalc.ovr(b, 'cam'), 127);
    });
  });

  group('PlayerCalc.diff (비교 팝업의 차이 숫자)', () {
    test('높은 쪽에만 차이를 준다', () {
      expect(PlayerCalc.diff(128, 132), (left: 0, right: 4));
      expect(PlayerCalc.diff(126, 125), (left: 1, right: 0));
      expect(PlayerCalc.diff(24, 24), (left: 0, right: 0));
    });
  });

  group('PlayerCalc.priceAt / basePositions', () {
    test('강화 단계별 시세 문자열에서 해당 단계 값', () {
      const ep = '0|1,030,000|1,030,000|1,080,000|2,000,000|9,690,000';
      expect(PlayerCalc.priceAt(ep, 1), 1030000);
      expect(PlayerCalc.priceAt(ep, 5), 9690000);
      expect(PlayerCalc.priceAt(ep, 9), isNull);
      expect(PlayerCalc.priceAt('', 1), isNull);
    });
    test('목록 줄의 OVR(0강 기준)에 강화 상승값을 더한다', () {
      final p = PlayerCalc.shownPositions([
        {'pos': 'ST', 'ovr': 119},
        {'pos': 'LW', 'ovr': 119},
      ], 8);
      expect(p, [(pos: 'ST', ovr: 137), (pos: 'LW', ovr: 137)]);
    });
  });
}
