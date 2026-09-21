// 양발 스탯 모델·배지·캐시 완성 판정 테스트 (2026-09-21)
// 실행: flutter test test/foot_badge_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fc_macro_app/models/foot_stat.dart';
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

  group('PlayerMetaStore.isComplete (foot 없으면 재요청 대상)', () {
    test('foot 키 없는 기존 캐시 → 미완성', () {
      expect(PlayerMetaStore.isComplete({'each_ovr': '1|2', 'traits': []}), isFalse);
    });
    test('foot 키가 null이어도(조회했으나 값 없음) → 완성', () {
      expect(PlayerMetaStore.isComplete({'each_ovr': '1|2', 'traits': [], 'foot': null}), isTrue);
    });
    test('foot 있음 → 완성', () {
      expect(PlayerMetaStore.isComplete({'each_ovr': '1|2', 'traits': [], 'foot': {'pref': 'L', 'left': 5, 'right': 4}}),
          isTrue);
    });
    test('each_ovr·traits 없으면 foot 있어도 미완성', () {
      expect(PlayerMetaStore.isComplete({'foot': {'pref': 'L', 'left': 5, 'right': 4}}), isFalse);
    });
  });

  group('FootBadge 위젯', () {
    Future<void> pump(WidgetTester t, FootStat? f) => t.pumpWidget(MaterialApp(
        home: Scaffold(body: Row(children: [FootBadge(foot: f)]))));

    testWidgets('null → 아무것도 그리지 않음', (t) async {
      await pump(t, null);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('메시: L5 굵게(w800), R4 흐리게(w500)', (t) async {
      await pump(t, FootStat.fromJson({'pref': 'L', 'left': 5, 'right': 4}));
      final rich = t.widget<Text>(find.byType(Text));
      final spans = (rich.textSpan as TextSpan).children!.cast<TextSpan>();
      expect(spans[0].text, 'L5');
      expect(spans[0].style!.fontWeight, FontWeight.w800);
      expect(spans[2].text, 'R4');
      expect(spans[2].style!.fontWeight, FontWeight.w500);
      expect(find.byType(Tooltip), findsOneWidget);
    });

    testWidgets('손흥민: R5 굵게', (t) async {
      await pump(t, FootStat.fromJson({'pref': 'R', 'left': 5, 'right': 5}));
      final rich = t.widget<Text>(find.byType(Text));
      final spans = (rich.textSpan as TextSpan).children!.cast<TextSpan>();
      expect(spans[0].style!.fontWeight, FontWeight.w500);
      expect(spans[2].style!.fontWeight, FontWeight.w800);
    });
  });
}
