// '선수(집훈)' 탭 화면 시험 (2026-09-30) — 폰 크기(390×844)에서 검색 결과·상세·비교·조건 화면이
// 넘침 없이 그려지고, 조절·탭 전환이 값에 반영되는지 본다.
// 서버 응답은 실제 서버에서 받아 둔 자료(test/fixtures/player_api.json, 2026-09-30)로 대신한다.
// 실행: flutter test test/player_screens_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fc_macro_app/models/player_query.dart';
import 'package:fc_macro_app/screens/player_detail_screen.dart';
import 'package:fc_macro_app/services/favorite_player_store.dart';
import 'package:fc_macro_app/widgets/player_compare_sheet.dart';
import 'package:fc_macro_app/widgets/player_filter_sheet.dart';
import 'package:fc_macro_app/widgets/player_tab.dart';

late Map<String, dynamic> _fx;

http.Client _client() => MockClient((req) async {
      final path = req.url.path;
      Object body = {'success': false};
      if (path.endsWith('/player/search')) body = _fx['search'];
      if (path.endsWith('/player/search-options')) body = _fx['options'];
      if (path.endsWith('/player/detail')) body = _fx['detail'];
      if (path.endsWith('/squad/card-teamcolors')) body = _fx['card_teamcolors'];
      if (path.endsWith('/player/price-history')) body = _fx['price_history'];
      return http.Response.bytes(utf8.encode(json.encode(body)), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

Map<String, dynamic> _row(int spid) => Map<String, dynamic>.from(
    ((_fx['search'] as Map)['players'] as List).firstWhere((p) => p['spid'] == spid) as Map);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// 가짜 서버 응답이 화면에 반영될 때까지 몇 번 그린다
Future<void> _settle(WidgetTester tester, [int times = 8]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

String _allText(WidgetTester tester) => [
      ...tester.widgetList<RichText>(find.byType(RichText)).map((r) => r.text.toPlainText()),
    ].join(' | ');

void main() {
  setUpAll(() {
    _fx = json.decode(File('test/fixtures/player_api.json').readAsStringSync()) as Map<String, dynamic>;
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FavoritePlayerStore.resetForTest();
  });

  testWidgets('검색 → 결과 목록 → 비교 고정', (tester) async {
    _phone(tester);
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PlayerTab())));
      await _settle(tester);
      await tester.enterText(find.byType(TextField).first, '손흥민, 메시');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await _settle(tester);

      final text = _allText(tester);
      expect(text, contains('9')); // 장수
      expect(find.text('1강 기준'), findsOneWidget);
      expect(find.text('OVR 높은 순'), findsOneWidget);
      expect(text, contains('리오넬 메시'));
      expect(text, contains('CF 126')); // 메시 UC 0강 123 + 1강 3
      expect(find.text('상세'), findsWidgets);

      await tester.tap(find.text('비교').first);
      await tester.pump();
      expect(find.text('비교 1'), findsOneWidget);
      expect(find.text('선택됨'), findsOneWidget);
    }, _client);
  });

  testWidgets('상세: 능력치·강화 조절·탭 4개', (tester) async {
    _phone(tester);
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(home: PlayerDetailScreen(row: _row(864200104))));
      await _settle(tester);

      var text = _allText(tester);
      expect(text, contains('손흥민'));
      expect(text, contains('ST 122'));
      expect(text, contains('1992.07.08'));
      expect(text, contains('탑클래스'));
      expect(text, contains('3372')); // 총 능력치 (1강)
      expect(find.text('다른 선수와 비교'), findsOneWidget);
      expect(find.text('집훈 계산'), findsOneWidget);

      // 강화를 8강까지 올리면 속력 143, ST 137
      for (var i = 0; i < 7; i++) {
        await tester.tap(find.byTooltip('강화 높이기'));
        await tester.pump();
      }
      text = _allText(tester);
      expect(text, contains('ST 137'));
      expect(text, contains('143'));

      await tester.tap(find.text('특성'));
      await _settle(tester, 3);
      expect(find.text('스피드스터'), findsOneWidget);
      expect(find.text('금색 아이콘은 신규특성입니다'), findsOneWidget);

      await tester.tap(find.text('시세'));
      await _settle(tester);
      expect(find.text('강화 단계별 현재가'), findsOneWidget);
      expect(find.text('30일'), findsOneWidget);

      await tester.ensureVisible(find.text('클럽 경력'));
      await tester.tap(find.text('클럽 경력'));
      await _settle(tester, 3);
      expect(find.text('LA FC'), findsOneWidget);
      expect(find.text('함부르크 SV II'), findsOneWidget);
    }, _client);
  });

  testWidgets('비교 팝업: 두 선수 값과 차이, 탭 전환', (tester) async {
    _phone(tester);
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () =>
                    showPlayerCompareSheet(context, first: _row(864200104), second: _row(866200104)),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('열기'));
      await _settle(tester);

      expect(find.text('선수 비교'), findsOneWidget);
      var text = _allText(tester);
      expect(text, contains('총 능력치'));
      expect(text, contains('3372')); // TK 1강
      expect(text, contains('스피드'));

      // 오른쪽 선수(26TOTS)를 5강으로 → 총 3510, 차이 +138
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byTooltip('강화 높이기').last);
        await tester.pump();
      }
      text = _allText(tester);
      expect(text, contains('3510'));
      expect(text, contains('+138'));

      await tester.tap(find.text('특성'));
      await _settle(tester, 3);
      expect(find.text('트릭스터'), findsOneWidget);
      await tester.tap(find.text('시세'));
      await _settle(tester, 3);
      expect(find.text('13강'), findsOneWidget);
      await tester.tap(find.text('클럽 경력'));
      await _settle(tester, 3);
      expect(find.text('LA FC'), findsNWidgets(2));
    }, _client);
  });

  testWidgets('조건 시트: 묶음·신규특성 아이콘 타일·조건 수', (tester) async {
    _phone(tester);
    PlayerQuery? picked;
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async => picked = await showPlayerFilterSheet(context, PlayerQuery(name: '손흥민')),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('열기'));
      await _settle(tester);

      expect(find.text('검색 조건'), findsOneWidget);
      expect(find.text('시즌'), findsOneWidget);
      expect(find.text('조건 없이 검색'), findsOneWidget);

      // 포지션 묶음은 시즌 아래라 내려야 보인다
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('ST'), 200, scrollable: list);
      expect(find.text('포지션'), findsOneWidget);
      await tester.tap(find.text('ST'));
      await tester.pump();
      await tester.scrollUntilVisible(find.text('스피드스터'), 200, scrollable: list);
      await tester.ensureVisible(find.text('스피드스터'));
      await tester.pump();
      expect(find.text('신규특성 17종'), findsOneWidget);
      await tester.tap(find.text('스피드스터'));
      await tester.pump();
      expect(find.text('조건 2개로 검색'), findsOneWidget);

      await tester.tap(find.text('조건 2개로 검색'));
      await _settle(tester, 4);
    }, _client);
    expect(picked, isNotNull);
    expect(picked!.positions, {'ST'});
    expect(picked!.traits, ['스피드스터']);
    expect(picked!.name, '손흥민');
  });
}
