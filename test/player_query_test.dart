// 선수 검색 조건·관심선수·최근 검색 테스트 (2026-09-30)
// 실행: flutter test test/player_query_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fc_macro_app/models/player_query.dart';
import 'package:fc_macro_app/services/favorite_player_store.dart';

void main() {
  group('PlayerQuery.parseNames', () {
    test('쉼표로 여러 명', () {
      expect(PlayerQuery.parseNames('손흥민, 메시'), ['손흥민', '메시']);
    });
    test('빈 값·중복 제거, 전각 쉼표 허용', () {
      expect(PlayerQuery.parseNames(' 손흥민 ,, 메시，손흥민'), ['손흥민', '메시']);
      expect(PlayerQuery.parseNames(''), isEmpty);
      expect(PlayerQuery.parseNames(null), isEmpty);
    });
    test('10명까지만', () {
      expect(PlayerQuery.parseNames(List.generate(30, (i) => '선수$i').join(',')).length, PlayerQuery.maxNames);
    });
  });

  group('PlayerQuery.toParams (서버 요청 인자)', () {
    test('이름만', () {
      expect(PlayerQuery(name: '손흥민, 메시').toParams(), {'name': '손흥민,메시'});
    });
    test('조건 조합', () {
      final q = PlayerQuery(name: '손흥민')
        ..seasons = {864, 866}
        ..positions = {'ST', 'CF'}
        ..grade = 8
        ..ovrMin = 130
        ..payMax = 30
        ..traits = ['스피드스터', '트릭스터', '타이탄', '블로커']
        ..abilities = [const AbilityCond('sprintspeed', min: 130)]
        ..bodyTypes = {'heavy'}
        ..mainFoot = 'L'
        ..sort = 'pay'
        ..desc = false;
      final p = q.toParams();
      expect(p['seasons'], '864,866');
      expect(p['positions'], 'ST,CF');
      expect(p['grade'], '8');
      expect(p['ovr_min'], '130');
      expect(p['pay_max'], '30');
      expect(p['traits'], '스피드스터,트릭스터,타이탄'); // 3개까지
      expect(p['abilities'], 'sprintspeed:130:');
      expect(p['body'], 'heavy');
      expect(p['main_foot'], 'L');
      expect(p['sort'], 'pay');
      expect(p['desc'], '0');
      expect(p.containsKey('ovr_max'), isFalse);
    });
    test('현재 소속만: 클럽을 골랐을 때만 history=0을 보낸다', () {
      final q = PlayerQuery()..clubHistory = false;
      expect(q.toParams().containsKey('history'), isFalse);
      q.teamId = 1;
      expect(q.toParams()['history'], '0');
    });
  });

  group('조건 수·빈 검색', () {
    test('이름은 조건 수에 넣지 않는다', () {
      final q = PlayerQuery(name: '손흥민');
      expect(q.conditionCount, 0);
      expect(q.isEmpty, isFalse);
      expect(PlayerQuery().isEmpty, isTrue);
    });
    test('묶음별로 센다', () {
      final q = PlayerQuery()
        ..seasons = {864, 866}
        ..positions = {'ST'}
        ..ovrMin = 120
        ..ovrMax = 130
        ..traits = ['스피드스터'];
      expect(q.conditionCount, 4);
      expect(q.isEmpty, isFalse);
    });
    test('조건 비우기: 이름·강화 기준·정렬은 남는다', () {
      final q = PlayerQuery(name: '손흥민')
        ..grade = 5
        ..sort = 'pay'
        ..positions = {'ST'}
        ..traits = ['스피드스터']
        ..heightMin = 190;
      q.clearConditions();
      expect(q.conditionCount, 0);
      expect(q.name, '손흥민');
      expect(q.grade, 5);
      expect(q.sort, 'pay');
    });
  });

  group('저장 형식', () {
    test('toJson → fromJson 왕복', () {
      final q = PlayerQuery(name: '손흥민, 메시')
        ..seasons = {864}
        ..positions = {'ST'}
        ..grade = 5
        ..teamId = 1
        ..teamName = '아스널'
        ..clubHistory = false
        ..traits = ['스피드스터']
        ..abilities = [const AbilityCond('stamina', max: 110)]
        ..desc = false;
      final r = PlayerQuery.fromJson(q.toJson());
      expect(r.toParams(), q.toParams());
      expect(r.teamName, '아스널');
      expect(r.key, q.key);
    });
    test('깨진 값은 빈 조건', () {
      expect(PlayerQuery.fromJson('x').isEmpty, isTrue);
    });
  });

  group('FavoritePlayerStore (관심선수 20명)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      FavoritePlayerStore.resetForTest();
    });

    test('등록·중복·삭제', () async {
      expect(await FavoritePlayerStore.add({'spid': 864200104, 'name': '손흥민'}), isTrue);
      expect(await FavoritePlayerStore.add({'spid': 864200104, 'name': '손흥민'}), isTrue);
      expect(FavoritePlayerStore.players.value.length, 1);
      expect(FavoritePlayerStore.contains(864200104), isTrue);
      await FavoritePlayerStore.remove(864200104);
      expect(FavoritePlayerStore.players.value, isEmpty);
    });

    test('20명을 넘기면 등록되지 않는다', () async {
      for (var i = 0; i < FavoritePlayerStore.max; i++) {
        expect(await FavoritePlayerStore.add({'spid': 100 + i, 'name': '선수$i'}), isTrue);
      }
      expect(FavoritePlayerStore.isFull, isTrue);
      expect(await FavoritePlayerStore.add({'spid': 999, 'name': '넘침'}), isFalse);
      expect(FavoritePlayerStore.players.value.length, FavoritePlayerStore.max);
      expect(FavoritePlayerStore.players.value.first['spid'], 100 + FavoritePlayerStore.max - 1); // 최근 등록이 앞
    });

    test('다시 불러와도 남아 있다', () async {
      await FavoritePlayerStore.add({'spid': 1, 'name': 'a'});
      FavoritePlayerStore.resetForTest();
      await FavoritePlayerStore.ensureLoaded();
      expect(FavoritePlayerStore.players.value.single['name'], 'a');
    });
  });

  group('PlayerRecentStore (최근 검색 8건)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('같은 검색은 최신으로 교체, 8건까지', () async {
      await PlayerRecentStore.add(PlayerQuery(name: '손흥민'));
      await PlayerRecentStore.add(PlayerQuery(name: '메시'));
      var list = await PlayerRecentStore.add(PlayerQuery(name: '손흥민'));
      expect(list.map((q) => q.name).toList(), ['손흥민', '메시']);
      for (var i = 0; i < 10; i++) {
        list = await PlayerRecentStore.add(PlayerQuery(name: '선수$i'));
      }
      expect(list.length, PlayerRecentStore.max);
      expect(list.first.name, '선수9');
      expect(await PlayerRecentStore.clear(), isEmpty);
    });
  });
}
