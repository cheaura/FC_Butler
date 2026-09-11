// 겹침 방지 배치·티어 명칭 유틸 검증 (2026-09-11)
import 'package:flutter_test/flutter_test.dart';
import 'package:fc_macro_app/constants/positions.dart';
import 'package:fc_macro_app/utils/tier_names.dart';

void main() {
  test('ST·CF 같은 자리 → 좌우 분산, 같은 줄 y 통일', () {
    final c = layoutRoleCoords(['gk', 'st', 'cf']);
    expect(c[0], [0.5, 1.0]); // GK 그대로
    final xs = [c[1][0], c[2][0]]..sort();
    expect(xs, [0.25, 0.75]);
    expect(c[1][1], c[2][1]); // 같은 줄
    expect(c[1][1], 0.0); // 최전방 y=85
  });
  test('간격 넉넉한 4백은 원 좌표 유지', () {
    final c = layoutRoleCoords(['rb', 'rcb', 'lcb', 'lb']);
    expect(c.map((e) => e[0]).toList(), [0.93, 0.68, 0.32, 0.07]);
  });
  test('3백(32/50/68)은 균등 분산', () {
    final c = layoutRoleCoords(['rcb', 'cb', 'lcb']);
    final xs = c.map((e) => e[0]).toList()..sort();
    expect(xs.map((x) => (x * 100).round()).toList(), [17, 50, 83]);
  });
  test('4-2-4 최전방 4명 균등 분산, 미드 3명 원 좌표', () {
    final roles = kFormations['4-2-4']!;
    final c = layoutRoleCoords(roles);
    final fw = [7, 8, 9, 10].map((i) => c[i][0]).toList()..sort();
    expect(fw, [0.125, 0.375, 0.625, 0.875]);
    expect(c[5][0], 0.73); // rcm 유지
  });
  test('티어 아이콘 번호 → 등급명', () {
    expect(tierNameFromIconUrl('https://ssl.nexon.com/s2/game/fo4/obt/rank/large/update_2026/ico_rank6_m.png'), '마스터1');
    expect(tierNameFromIconUrl('//x/ico_rank0.png'), '슈퍼 챔피언스');
    expect(tierNameFromIconUrl('//x/ico_rank9_m.png'), '월드클래스1');
    expect(tierNameFromIconUrl('//x/ico_rank20.png'), '유망주3');
    expect(tierNameFromIconUrl('//x/ico_rank21.png'), isNull);
    expect(tierNameFromIconUrl(''), isNull);
    expect(tierLabel('월드클래스 1부', '//x/ico_rank6_m.png'), '마스터1');
    expect(tierLabel('월드클래스 1부', null), '월드클래스 1부');
  });
}
