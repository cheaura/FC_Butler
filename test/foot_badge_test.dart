// 양발 스탯·참여도 모델·배지·캐시 완성 판정 테스트 (2026-09-21, 09-28 발 모양·참여도로 갱신)
// 실행: flutter test test/foot_badge_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fc_macro_app/models/foot_stat.dart';
import 'package:fc_macro_app/models/work_rate.dart';
import 'package:fc_macro_app/services/player_meta_store.dart';
import 'package:fc_macro_app/widgets/foot_badge.dart';

void main() {
  group('FootStat.fromJson', () {
    test('메시: 왼발 주발 L5 R4', () {
      final f = FootStat.fromJson({'pref': 'L', 'left': 5, 'right': 4})!;
      expect(f.prefIsLeft, isTrue);
      expect(f.label, 'L5 R4');
      expect(f.description, contains('주발 왼발'));
    });
    test('손흥민: 오른발 주발 L5 R5', () {
      final f = FootStat.fromJson({'pref': 'R', 'left': 5, 'right': 5})!;
      expect(f.prefIsLeft, isFalse);
      expect(f.label, 'L5 R5');
    });
    test('문자열 숫자도 허용', () {
      expect(FootStat.fromJson({'pref': 'R', 'left': '2', 'right': '5'})!.label, 'L2 R5');
    });
    test('형식 이상 → null', () {
      expect(FootStat.fromJson(null), isNull);
      expect(FootStat.fromJson('x'), isNull);
      expect(FootStat.fromJson({'pref': 'X', 'left': 5, 'right': 4}), isNull);
      expect(FootStat.fromJson({'pref': 'L', 'left': 0, 'right': 4}), isNull);
      expect(FootStat.fromJson({'pref': 'L', 'left': 5}), isNull);
    });
  });

  group('WorkRate.fromJson (2026-09-28)', () {
    test('음바페 TOTY: 공격 3 · 수비 1', () {
      final w = WorkRate.fromJson({'att': 3, 'def': 1})!;
      expect(w.att, 3);
      expect(w.def, 1);
      expect(w.description, '공격 참여도 높음 · 수비 참여도 낮음');
    });
    test('범위 밖·형식 이상 → null', () {
      expect(WorkRate.fromJson(null), isNull);
      expect(WorkRate.fromJson({'att': 4, 'def': 1}), isNull);
      expect(WorkRate.fromJson({'att': 3}), isNull);
    });
  });

  group('PlayerMetaStore.isComplete (foot·workrate 없으면 재요청 대상)', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    const wr = {'att': 3, 'def': 1};
    test('foot 키 없는 기존 캐시 → 미완성', () {
      expect(PlayerMetaStore.isComplete({'each_ovr': '1|2', 'traits': [], 'workrate': wr}), isFalse);
    });
    test('foot null(조회했으나 값 없음) + 참여도 있음 → 완성', () {
      expect(PlayerMetaStore.isComplete({'each_ovr': '1|2', 'traits': [], 'foot': null, 'workrate': wr}), isTrue);
    });
    test('참여도 없고 확인 기록도 없음(수집 전 캐시) → 미완성', () {
      expect(PlayerMetaStore.isComplete({'each_ovr': '1|2', 'traits': [], 'foot': null}), isFalse);
    });
    test('참여도 없지만 방금 확인함 → 완성 (반복 요청 방지)', () {
      expect(PlayerMetaStore.isComplete({'each_ovr': '1|2', 'traits': [], 'foot': null, 'workrate': null, '_wr_at': now}),
          isTrue);
    });
    test('참여도 없고 확인한 지 하루 넘음 → 미완성 (수집됐는지 다시 확인)', () {
      final old = now - const Duration(days: 1, minutes: 1).inMilliseconds;
      expect(PlayerMetaStore.isComplete({'each_ovr': '1|2', 'traits': [], 'foot': null, 'workrate': null, '_wr_at': old}),
          isFalse);
    });
    test('each_ovr·traits 없으면 미완성', () {
      expect(PlayerMetaStore.isComplete({'foot': {'pref': 'L', 'left': 5, 'right': 4}, 'workrate': wr}), isFalse);
    });
  });

  group('FootBadge 위젯 (발 모양 + 참여도, 2026-09-28)', () {
    Future<void> pump(WidgetTester t, FootStat? f, WorkRate? w) => t.pumpWidget(MaterialApp(
        home: Scaffold(body: Row(children: [FootBadge(foot: f, workrate: w)]))));

    testWidgets('둘 다 null → 아무것도 그리지 않음', (t) async {
      await pump(t, null, null);
      expect(find.byType(FeetIcon), findsNothing);
      expect(find.byType(WorkRateIcon), findsNothing);
    });

    testWidgets('양발만 → 발 두 짝, 안내 문구', (t) async {
      await pump(t, FootStat.fromJson({'pref': 'L', 'left': 5, 'right': 4}), null);
      expect(find.byType(FeetIcon), findsOneWidget);
      expect(find.byType(WorkRateIcon), findsNothing);
      expect(find.byTooltip('양발: 왼발 5 · 오른발 4 (주발 왼발)'), findsOneWidget);
    });

    testWidgets('양발 + 참여도 → 둘 다, 크기 비율(발 폭 = 높이 0.7)', (t) async {
      await pump(t, FootStat.fromJson({'pref': 'R', 'left': 5, 'right': 5}), WorkRate.fromJson({'att': 3, 'def': 1}));
      expect(find.byType(FeetIcon), findsOneWidget);
      expect(find.byType(WorkRateIcon), findsOneWidget);
      expect(find.byTooltip('공격 참여도 높음 · 수비 참여도 낮음'), findsOneWidget);
      // 발 두 짝(20×0.7=14) + 간격 1
      expect(t.getSize(find.byType(FeetIcon)).width, closeTo(29, 0.01));
    });
  });
}
