// '선수(집훈)' 탭 화면 흐름 테스트 (2026-09-30) — 관심선수 표시와 비교 첫 번째 선수 고정·해제
// (검색·비교 팝업은 서버 호출이 필요해 여기서는 다루지 않는다)
// 실행: flutter test test/player_tab_test.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fc_macro_app/services/favorite_player_store.dart';
import 'package:fc_macro_app/widgets/player_tab.dart';

Map<String, dynamic> _card(int spid, String name, String season, int ovr) => {
      'spid': spid,
      'name': name,
      'season_img': season,
      'face_url': '',
      'positions': [
        {'pos': 'ST', 'ovr': ovr}
      ],
      'pay': 32,
      'each_price': '0|1,030,000',
    };

Future<void> _pumpTab(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PlayerTab())));
  // 저장소 읽기(비동기)가 끝나 화면에 반영될 때까지
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'favorite_players_v1': json.encode([
        _card(864200104, '손흥민', 'TK', 119),
        _card(866158023, '리오넬 메시', '26TOTS', 120),
      ]),
    });
    FavoritePlayerStore.resetForTest();
  });

  testWidgets('검색 전 화면: 위 전환 두 칸, 검색칸, 관심선수 목록', (tester) async {
    await _pumpTab(tester);
    expect(find.text('선수 검색'), findsOneWidget);
    expect(find.text('집훈 계산기'), findsWidgets);
    expect(find.text('선수 이름 (쉼표로 여러 명)'), findsOneWidget);
    expect(find.text('관심선수'), findsOneWidget);
    expect(find.text('2 / 20'), findsOneWidget);
    expect(find.text('손흥민'), findsOneWidget);
    expect(find.text('리오넬 메시'), findsOneWidget);
    expect(find.text('상세'), findsNWidgets(2));
  });

  testWidgets('비교 버튼 → 첫 선수가 위에 고정, 나머지 줄은 비교 강조 / 해제하면 원래대로', (tester) async {
    await _pumpTab(tester);
    expect(find.text('비교 1'), findsNothing);

    await tester.tap(find.text('비교').first); // 손흥민 줄
    await tester.pump();

    expect(find.text('비교 1'), findsOneWidget);
    expect(find.text('비교할 두 번째 선수의 비교 버튼을 누르세요'), findsOneWidget);
    expect(find.text('선택됨'), findsOneWidget); // 고른 줄
    expect(find.widgetWithText(FilledButton, '비교'), findsOneWidget); // 다른 줄은 강조
    expect(find.text('손흥민'), findsNWidgets(2)); // 고정 띠 + 목록

    await tester.tap(find.text('해제'));
    await tester.pump();
    expect(find.text('비교 1'), findsNothing);
    expect(find.text('선택됨'), findsNothing);
  });

  testWidgets('별을 누르면 관심선수에서 빠진다', (tester) async {
    await _pumpTab(tester);
    await tester.tap(find.byTooltip('관심선수 해제').first);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.text('1 / 20'), findsOneWidget);
    expect(find.text('손흥민'), findsNothing);
  });

  testWidgets('이름도 조건도 없이 검색하면 안내만 띄운다', (tester) async {
    await _pumpTab(tester);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.tap(find.byType(TextField).first);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(find.text('선수명이나 조건을 입력하세요.'), findsOneWidget);
  });
}
