// 선수 목록 줄 위젯 테스트 (2026-09-30) — 표시 값과 상세·비교·관심 버튼 동작
// 실행: flutter test test/player_list_row_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fc_macro_app/widgets/player_list_row.dart';

// 서버 검색 결과 한 줄 (손흥민 TK — OVR은 0강 기준 119)
const _row = <String, dynamic>{
  'spid': 864200104,
  'name': '손흥민',
  'season_img': 'TK',
  'face_url': '',
  'positions': [
    {'pos': 'ST', 'ovr': 119},
    {'pos': 'LW', 'ovr': 119},
  ],
  'pay': 32,
  'foot': {'pref': 'R', 'left': 5, 'right': 5},
  'workrate': {'att': 2, 'def': 2},
  'each_price': '0|1,030,000|1,030,000|1,080,000|2,000,000|9,690,000|26,700,000|149,000,000|736,000,000',
};

Future<Map<String, int>> _pump(WidgetTester tester,
    {int grade = 1, bool favorite = false, PlayerCompareMode compare = PlayerCompareMode.none}) async {
  final taps = {'detail': 0, 'compare': 0, 'favorite': 0};
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: PlayerListRow(
        row: _row,
        grade: grade,
        favorite: favorite,
        compare: compare,
        onDetail: () => taps['detail'] = taps['detail']! + 1,
        onCompare: () => taps['compare'] = taps['compare']! + 1,
        onFavorite: () => taps['favorite'] = taps['favorite']! + 1,
      ),
    ),
  ));
  await tester.pump();
  return taps;
}

/// Text.rich까지 포함해 화면의 글자를 한 줄로 모은다
String _allText(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((r) => r.text.toPlainText())
    .join(' | ');

void main() {
  testWidgets('이름·급여·버튼이 보이고, OVR은 강화 기준 값으로 표시된다', (tester) async {
    await _pump(tester, grade: 1);
    final text = _allText(tester);
    expect(text, contains('손흥민'));
    expect(text, contains('ST 122')); // 0강 119 + 1강 상승값 3
    expect(text, contains('LW 122'));
    expect(text, contains('급여 32'));
    expect(text, contains('103만')); // 1강 시세
    expect(find.text('상세'), findsOneWidget);
    expect(find.text('비교'), findsOneWidget);
  });

  testWidgets('8강 기준: OVR 137, 시세는 8강 값', (tester) async {
    await _pump(tester, grade: 8);
    final text = _allText(tester);
    expect(text, contains('ST 137'));
    expect(text, contains('7억 3600만'));
  });

  testWidgets('상세·비교·관심 버튼이 각각의 동작을 부른다', (tester) async {
    final taps = await _pump(tester);
    await tester.tap(find.text('상세'));
    await tester.tap(find.text('비교'));
    await tester.tap(find.byTooltip('관심선수 등록'));
    expect(taps, {'detail': 1, 'compare': 1, 'favorite': 1});
  });

  testWidgets('비교 첫 번째로 고른 줄: 선택됨 표시, 비교 버튼은 눌리지 않는다', (tester) async {
    final taps = await _pump(tester, compare: PlayerCompareMode.picked);
    expect(find.text('선택됨'), findsOneWidget);
    expect(find.text('비교'), findsNothing);
    await tester.tap(find.text('선택됨'));
    expect(taps['compare'], 0);
  });

  testWidgets('첫 선수가 정해진 뒤의 다른 줄: 비교 버튼이 강조되고 눌린다', (tester) async {
    final taps = await _pump(tester, compare: PlayerCompareMode.target);
    expect(find.widgetWithText(FilledButton, '비교'), findsOneWidget);
    await tester.tap(find.text('비교'));
    expect(taps['compare'], 1);
  });

  testWidgets('관심선수로 등록된 줄은 해제 버튼을 보여준다', (tester) async {
    await _pump(tester, favorite: true);
    expect(find.byTooltip('관심선수 해제'), findsOneWidget);
  });
}
